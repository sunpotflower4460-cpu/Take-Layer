import type { ServiceHealth } from '../contracts/service.js'
import type { SystemId } from '../core/common.js'
import { OWNERSHIP_RULES } from '../ledger/ownership.js'
import type { RuntimeMode } from '../ledger/ownership.js'

export interface OwnershipFinding {
  severity: 'blocker' | 'warning'
  code: 'NOT_MANAGED' | 'MODE_INVALID' | 'FORBIDDEN_INBOUND_EXECUTION' | 'DUAL_META_RECEIVER' | 'NOT_CANONICAL_RECEIVER' | 'DUPLICATE_EXECUTOR' | 'UNREPORTED'
  system: SystemId
  message: string
}

const truthyFor = (v: boolean | Record<string, boolean> | undefined, platform?: string) =>
  typeof v === 'boolean' ? v : v && platform ? v[platform] === true : v ? Object.values(v).some(Boolean) : false

/**
 * Cross-checks what each system SAYS about itself (health) against the managed-mode ownership rules.
 * It reports; it never changes a specialist. Blockers mean "do not enable write coordination yet".
 *
 *  - every expected system must report runtimeMode=artist_os_managed (explicit, not inferred)
 *  - SNS-AI must report inboundReplyExecution=false
 *  - SNS-providers must not execute Instagram inbound replies, nor be the canonical Meta receiver
 *  - My-SNS must be the canonical Meta receiver
 *  - no two systems may both claim to execute the same (platform) inbound reply
 */
export function checkOwnershipConsistency(healths: Partial<Record<SystemId, ServiceHealth>>): OwnershipFinding[] {
  const out: OwnershipFinding[] = []
  const expected: SystemId[] = ['my-sns', 'sns-providers', 'sns-ai']
  for (const sys of expected) {
    const h = healths[sys]
    if (!h) {
      out.push({ severity: 'warning', code: 'UNREPORTED', system: sys, message: `${sys} has not reported health; ownership cannot be verified` })
      continue
    }
    if (h.modeInvalid) out.push({ severity: 'blocker', code: 'MODE_INVALID', system: sys, message: `${sys} reports an invalid ARTIST_OS_MODE value` })
    if (h.runtimeMode !== 'artist_os_managed') {
      out.push({ severity: 'blocker', code: 'NOT_MANAGED', system: sys, message: `${sys} is ${h.runtimeMode ?? 'not reporting a runtime mode'}; managed-mode ownership is not in force` })
    }
  }
  const ai = healths['sns-ai']
  if (ai && truthyFor(ai.ownership?.inboundReplyExecution)) {
    out.push({ severity: 'blocker', code: 'FORBIDDEN_INBOUND_EXECUTION', system: 'sns-ai', message: 'SNS-AI reports it can execute inbound replies' })
  }
  const prov = healths['sns-providers']
  if (prov) {
    if (truthyFor(prov.ownership?.inboundReplyExecution, 'instagram') || prov.capabilities.some((c) => /^reply\.instagram\..*\.execute$/.test(c))) {
      out.push({ severity: 'blocker', code: 'FORBIDDEN_INBOUND_EXECUTION', system: 'sns-providers', message: 'SNS-providers can execute Instagram inbound replies, which My-SNS owns' })
    }
    if (prov.ownership?.canonicalMetaWebhookReceiver === true) {
      out.push({ severity: 'blocker', code: 'DUAL_META_RECEIVER', system: 'sns-providers', message: 'SNS-providers claims to be the canonical Meta webhook receiver' })
    }
  }
  const sns = healths['my-sns']
  if (sns && sns.runtimeMode === 'artist_os_managed' && sns.ownership?.canonicalMetaWebhookReceiver !== true) {
    out.push({ severity: 'blocker', code: 'NOT_CANONICAL_RECEIVER', system: 'my-sns', message: 'My-SNS is managed but does not report itself as the canonical Meta webhook receiver' })
  }
  // Duplicate executors per platform from declared capabilities.
  for (const platform of new Set(OWNERSHIP_RULES.map((r) => r.platform))) {
    const executors = (['my-sns', 'sns-providers', 'sns-ai'] as SystemId[]).filter((sys) => {
      const h = healths[sys]
      return !!h && (h.capabilities.some((c) => new RegExp(`^reply\\.${platform}\\.[a-z_]+\\.execute$`).test(c)) || truthyFor(h.ownership?.inboundReplyExecution, platform))
    })
    if (executors.length > 1) out.push({ severity: 'blocker', code: 'DUPLICATE_EXECUTOR', system: executors[0]!, message: `${executors.join(' + ')} all claim to execute ${platform} inbound replies` })
  }
  return out
}

export type { RuntimeMode }
