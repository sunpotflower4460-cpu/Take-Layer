import { z } from 'zod'
import type { RiskClass } from '../policy/gateway.js'

/**
 * MCP / external-equipment gateway foundation.
 *
 * Remote output is UNTRUSTED. The only way for external data to enter Artist OS
 * is: raw → normalize → validate → classify → policy → artifact.
 * Nothing in this file executes, evals or forwards external text.
 */
export type TransportKind = 'REMOTE_MCP' | 'REST_WEBHOOK' | 'EXTERNAL_HANDOFF'

export interface RawEquipmentResponse {
  equipmentId: string
  capability: string
  transport: TransportKind
  raw: unknown
}

/** Transport adapter: gets bytes from the outside. Contains NO business logic. */
export interface EquipmentTransport {
  kind: TransportKind
  call(equipmentId: string, capability: string, input: unknown): Promise<RawEquipmentResponse>
}

export const DATA_CLASSES = ['ARTIST_OWNED', 'OPEN_INTELLIGENCE', 'PROVIDER_OPERATIONAL', 'PROVIDER_DERIVED_RESTRICTED', 'PRIVATE_MEDIA', 'PUBLIC_CONTENT', 'SECRET'] as const
export type DataClass = (typeof DATA_CLASSES)[number]
const AI_SAFE: ReadonlySet<DataClass> = new Set(['ARTIST_OWNED', 'OPEN_INTELLIGENCE', 'PUBLIC_CONTENT'])
export const isAiSafe = (c: DataClass) => AI_SAFE.has(c)

export const ResearchArtifactSchema = z.object({
  schemaVersion: z.literal(1),
  kind: z.literal('ResearchArtifact'),
  capability: z.string(),
  source: z.object({ equipmentId: z.string(), transport: z.enum(['REMOTE_MCP', 'REST_WEBHOOK', 'EXTERNAL_HANDOFF']) }),
  dataClass: z.enum(DATA_CLASSES),
  /** Structured, size-bounded findings only. */
  findings: z.array(z.object({ title: z.string().max(200), value: z.union([z.string().max(1000), z.number(), z.boolean()]) })).max(100),
  /** Always false for external output: it cannot authorize any write by itself. */
  authorizesAction: z.literal(false),
})
export type ResearchArtifact = z.infer<typeof ResearchArtifactSchema>

const INJECTION_PATTERNS: RegExp[] = [
  /ignore (all|any|previous|prior) (instructions|rules)/i,
  /\b(rm\s+-rf|curl\s+[^|]*\|\s*(ba)?sh|sudo\s)/i,
  /\b(api[_-]?key|secret|token|password)\s*[:=]/i,
  /(system prompt|developer message)/i,
]

export interface IngestOutcome {
  artifact?: ResearchArtifact
  rejected?: { stage: 'normalize' | 'validate' | 'classify' | 'policy'; reason: string }
  /** Findings dropped because they looked like instructions/secrets rather than data. */
  quarantined: string[]
}

export interface IngestOptions {
  /** Declared data class for this capability's output. Unknown ⇒ most restrictive. */
  dataClassFor?: (capability: string) => DataClass | undefined
  /** Whether policy lets this artifact in (e.g. READ risk). */
  policyCheck?: (risk: RiskClass, capability: string) => 'allow' | 'deny'
}

/** The single entry point for external equipment output. */
export function ingestEquipmentResponse(resp: RawEquipmentResponse, opts: IngestOptions = {}): IngestOutcome {
  const quarantined: string[] = []

  // 1. normalize: accept only a plain JSON object with a `findings` array of {title,value}.
  const raw = resp.raw
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return { rejected: { stage: 'normalize', reason: 'response is not a JSON object' }, quarantined }
  }
  const rawFindings = (raw as { findings?: unknown }).findings
  if (!Array.isArray(rawFindings)) return { rejected: { stage: 'normalize', reason: 'missing findings array' }, quarantined }
  const findings: { title: string; value: string | number | boolean }[] = []
  for (const f of rawFindings.slice(0, 100)) {
    if (!f || typeof f !== 'object') continue
    const { title, value } = f as { title?: unknown; value?: unknown }
    if (typeof title !== 'string' || !(typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean')) continue
    const text = `${title} ${typeof value === 'string' ? value : ''}`
    if (INJECTION_PATTERNS.some((p) => p.test(text))) {
      quarantined.push(title.slice(0, 80))
      continue
    }
    findings.push({ title: title.slice(0, 200), value: typeof value === 'string' ? value.slice(0, 1000) : value })
  }

  // 3. classify (before validate result is trusted): unknown class ⇒ restricted.
  const dataClass: DataClass = opts.dataClassFor?.(resp.capability) ?? 'PROVIDER_DERIVED_RESTRICTED'

  // 2. validate against the typed artifact schema.
  const parsed = ResearchArtifactSchema.safeParse({
    schemaVersion: 1,
    kind: 'ResearchArtifact',
    capability: resp.capability,
    source: { equipmentId: resp.equipmentId, transport: resp.transport },
    dataClass,
    findings,
    authorizesAction: false,
  })
  if (!parsed.success) return { rejected: { stage: 'validate', reason: parsed.error.issues[0]?.message ?? 'invalid' }, quarantined }

  // 4. policy: external output is a READ-class input only.
  if (opts.policyCheck && opts.policyCheck('READ', resp.capability) === 'deny') {
    return { rejected: { stage: 'policy', reason: 'policy denied ingestion' }, quarantined }
  }
  return { artifact: parsed.data, quarantined }
}

/**
 * Build the AI context for a capability. Allowlist-based: restricted classes are
 * never passed on, regardless of how the data was obtained.
 */
export function toAiContext(artifacts: readonly ResearchArtifact[]): ResearchArtifact[] {
  return artifacts.filter((a) => isAiSafe(a.dataClass))
}
