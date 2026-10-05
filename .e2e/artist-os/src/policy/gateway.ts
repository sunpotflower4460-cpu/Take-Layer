import { z } from 'zod'

/**
 * Policy Gateway.
 *
 * Effective policy = Artist OS ∩ specialist ∩ provider capability ∩ auth ∩ quota ∩ billing.
 * The MOST RESTRICTIVE layer wins. Artist OS may only tighten, never loosen.
 */
export const RISK_CLASSES = ['READ', 'GENERATE', 'WRITE_REVERSIBLE', 'WRITE_EXTERNAL', 'DESTRUCTIVE', 'FINANCIAL'] as const
export type RiskClass = (typeof RISK_CLASSES)[number]

/** Ordered from least to most restrictive. */
export const VERDICTS = ['allow', 'approval', 'handoff', 'deny'] as const
export type Verdict = (typeof VERDICTS)[number]
const RANK: Record<Verdict, number> = { allow: 0, approval: 1, handoff: 2, deny: 3 }

export const POLICY_LAYERS = ['artist_os', 'specialist', 'provider', 'auth', 'quota', 'billing'] as const
export type PolicyLayer = (typeof POLICY_LAYERS)[number]

export interface LayerDecision {
  layer: PolicyLayer
  verdict: Verdict
  reason: string
}

export const mostRestrictive = (a: Verdict, b: Verdict): Verdict => (RANK[a] >= RANK[b] ? a : b)

export interface PolicyRequest {
  /** Capability or operation id, e.g. "x.like", "instagram.dm.reply", "my-sns.publish". */
  operation: string
  risk: RiskClass
  /** Target specialist, if any. */
  system?: string
}

export type LayerEvaluator = (req: PolicyRequest) => LayerDecision | undefined

export interface EffectivePolicy {
  request: PolicyRequest
  verdict: Verdict
  /** All layer decisions, including `allow`s, for auditability. */
  decisions: LayerDecision[]
  /** The decisions that determined the verdict (those equal to the effective verdict). */
  binding: LayerDecision[]
}

/** Artist OS baseline: the floor, applied before any specialist is consulted. */
export const ARTIST_OS_BASELINE: Record<RiskClass, Verdict> = {
  READ: 'allow',
  GENERATE: 'allow',
  WRITE_REVERSIBLE: 'approval',
  WRITE_EXTERNAL: 'approval',
  DESTRUCTIVE: 'deny',
  /** NEVER_AUTO_PURCHASE: money is only ever moved by a human, outside Artist OS. */
  FINANCIAL: 'deny',
}

export function artistOsLayer(overrides: Partial<Record<RiskClass, Verdict>> = {}): LayerEvaluator {
  return (req) => {
    const base = ARTIST_OS_BASELINE[req.risk]
    const o = overrides[req.risk]
    // An override may only tighten the baseline.
    const verdict = o ? mostRestrictive(base, o) : base
    return { layer: 'artist_os', verdict, reason: `Artist OS baseline for ${req.risk}` }
  }
}

/**
 * Operation-level provider capability table. Unsupported operations become
 * HANDOFF (a human does it in the platform), never browser automation.
 */
export interface ProviderOperationRule {
  verdict: Verdict
  reason: string
}
export function providerLayer(rules: Record<string, ProviderOperationRule>): LayerEvaluator {
  return (req) => {
    const rule = rules[req.operation]
    if (!rule) return undefined
    return { layer: 'provider', verdict: rule.verdict, reason: rule.reason }
  }
}

/** Provider rules Artist OS ships as an (intentionally conservative) default. Versioned data, not logic. */
export const DEFAULT_PROVIDER_RULES_VERSION = 1
export const DEFAULT_PROVIDER_RULES: Record<string, ProviderOperationRule> = {
  'x.like': { verdict: 'handoff', reason: 'Automated likes are not automated by Artist OS; the human does it on the platform' },
  'instagram.like': { verdict: 'handoff', reason: 'No supported API for likes' },
  'instagram.follow': { verdict: 'handoff', reason: 'No supported API for follow' },
  'instagram.unfollow': { verdict: 'handoff', reason: 'No supported API for unfollow' },
  'x.follow': { verdict: 'handoff', reason: 'Follow defaults to human handoff unless a current official policy permits it' },
  'x.unfollow': { verdict: 'handoff', reason: 'Follow state changes default to human handoff' },
  'instagram.dm.send_unsolicited': { verdict: 'deny', reason: 'Unsolicited DMs are not supported' },
  'x.dm.send_unsolicited': { verdict: 'handoff', reason: 'Unsolicited DMs default to human handoff' },
}

export function specialistLayer(system: string, rules: Record<string, ProviderOperationRule>): LayerEvaluator {
  return (req) => {
    if (req.system !== system) return undefined
    const rule = rules[req.operation]
    return rule ? { layer: 'specialist', verdict: rule.verdict, reason: rule.reason } : undefined
  }
}

export interface AuthState {
  /** operation prefix or system → whether a usable credential exists. */
  isAuthenticated(req: PolicyRequest): boolean
}
export const authLayer =
  (auth: AuthState): LayerEvaluator =>
  (req) =>
    auth.isAuthenticated(req)
      ? { layer: 'auth', verdict: 'allow', reason: 'credential present' }
      : { layer: 'auth', verdict: 'deny', reason: 'AUTH_REQUIRED' }

export interface QuotaState {
  isExhausted(req: PolicyRequest): boolean
}
export const quotaLayer =
  (quota: QuotaState): LayerEvaluator =>
  (req) =>
    quota.isExhausted(req) ? { layer: 'quota', verdict: 'deny', reason: 'QUOTA_EXHAUSTED' } : { layer: 'quota', verdict: 'allow', reason: 'quota available' }

/** Billing: anything FINANCIAL is denied for automation. Paid usage that is already active is not new spend. */
export const billingLayer =
  (opts: { incursNewCost?: (req: PolicyRequest) => boolean } = {}): LayerEvaluator =>
  (req) => {
    if (req.risk === 'FINANCIAL' || opts.incursNewCost?.(req)) {
      return { layer: 'billing', verdict: 'deny', reason: 'NEVER_AUTO_PURCHASE' }
    }
    return { layer: 'billing', verdict: 'allow', reason: 'no new spend' }
  }

export class PolicyGateway {
  constructor(private readonly layers: readonly LayerEvaluator[]) {}

  evaluate(request: PolicyRequest): EffectivePolicy {
    // The Artist OS baseline always applies, even if the caller forgot to register it.
    const decisions: LayerDecision[] = [artistOsLayer()(request)!]
    for (const layer of this.layers) {
      const d = layer(request)
      if (d) decisions.push(d)
    }
    const verdict = decisions.reduce<Verdict>((acc, d) => mostRestrictive(acc, d.verdict), 'allow')
    return { request, verdict, decisions, binding: decisions.filter((d) => d.verdict === verdict) }
  }
}

export const PolicyRequestSchema = z.object({
  operation: z.string().min(1).max(128),
  risk: z.enum(RISK_CLASSES),
  system: z.string().optional(),
})
