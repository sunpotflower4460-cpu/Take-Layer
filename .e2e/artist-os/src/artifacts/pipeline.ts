import { z } from 'zod'
import { IsoTimestampSchema, OpaqueIdSchema, SCHEMA_VERSION, SourceRefSchema, SystemIdSchema } from '../core/common.js'
import type { PolicyGateway, PolicyRequest, Verdict } from '../policy/gateway.js'

/**
 * Artifact-first: AI output never mutates anything directly.
 *   AI → Artifact → Validation → Policy → Decision → Action
 * This file defines the common envelope and the pipeline; the typed payloads
 * (EditProposal, GrowthStrategy, ...) are owned by the producing specialist and
 * referenced here by kind + schemaVersion, then validated by a registered schema.
 */
export const ARTIFACT_KINDS = [
  'VideoAnalysisArtifact',
  'HighlightCandidateArtifact',
  'EditProposalArtifact',
  'TrackIntelligenceArtifact',
  'ResearchArtifact',
  'RelationshipEnrichmentArtifact',
  'AudioAnalysisArtifact',
  'ResolverCalibrationSummaryArtifact',
  'RenderedMediaArtifact',
  'GrowthStrategyArtifact',
  'ActionRecommendation',
] as const
export type ArtifactKind = (typeof ARTIFACT_KINDS)[number]

export const ArtifactEnvelopeSchema = z.object({
  schemaVersion: z.literal(SCHEMA_VERSION),
  artifactId: OpaqueIdSchema,
  kind: z.enum(ARTIFACT_KINDS),
  producer: SystemIdSchema,
  createdAt: IsoTimestampSchema,
  subjectRefs: z.array(SourceRefSchema).max(20).default([]),
  traceId: OpaqueIdSchema.optional(),
  payloadVersion: z.number().int().min(1),
  payload: z.unknown(),
})
export type ArtifactEnvelope = z.infer<typeof ArtifactEnvelopeSchema>

/** What a validated artifact proposes. Produced by a registered interpreter, never by the AI directly. */
export interface ProposedAction {
  operation: string
  risk: PolicyRequest['risk']
  system: PolicyRequest['system']
  summary: string
}

export interface ArtifactHandler {
  kind: ArtifactKind
  payloadSchema: z.ZodType
  /** Pure: turn a validated payload into the ACTIONS it asks for. */
  propose(payload: unknown, envelope: ArtifactEnvelope): ProposedAction[]
}

export type PipelineOutcome =
  | { stage: 'rejected'; reason: 'invalid_envelope' | 'unknown_kind' | 'invalid_payload'; detail: string }
  | { stage: 'decided'; proposals: { action: ProposedAction; verdict: Verdict; reasons: string[] }[] }

export class ArtifactPipeline {
  private readonly handlers = new Map<ArtifactKind, ArtifactHandler>()
  constructor(private readonly policy: PolicyGateway) {}
  register(h: ArtifactHandler): this {
    this.handlers.set(h.kind, h)
    return this
  }
  /**
   * Returns verdicts only. A verdict of `allow`/`approval` is a permission to PROCEED
   * through the specialist's own approval flow, not an action taken here.
   */
  process(raw: unknown): PipelineOutcome {
    const env = ArtifactEnvelopeSchema.safeParse(raw)
    if (!env.success) return { stage: 'rejected', reason: 'invalid_envelope', detail: env.error.issues[0]?.message ?? 'invalid' }
    const handler = this.handlers.get(env.data.kind)
    if (!handler) return { stage: 'rejected', reason: 'unknown_kind', detail: env.data.kind }
    const payload = handler.payloadSchema.safeParse(env.data.payload)
    if (!payload.success) return { stage: 'rejected', reason: 'invalid_payload', detail: payload.error.issues[0]?.message ?? 'invalid' }
    const proposals = handler.propose(payload.data, env.data).map((action) => {
      const eff = this.policy.evaluate({ operation: action.operation, risk: action.risk, system: action.system })
      return { action, verdict: eff.verdict, reasons: eff.binding.map((b) => `${b.layer}: ${b.reason}`) }
    })
    return { stage: 'decided', proposals }
  }
}
