import { z } from 'zod'
import { ACTION_PLATFORMS } from '../ledger/action-key.js'
import { ArtifactEnvelopeSchema } from '../artifacts/pipeline.js'
import { IsoTimestampSchema, OpaqueIdSchema } from '../core/common.js'

/**
 * RelationshipEnrichmentArtifact (payload v1) — produced by SNS-providers (relationship intelligence) about ONE
 * inbound event that My-SNS owns. It is INTELLIGENCE ONLY:
 *   - it never edits My-SNS's Inbox row, never carries reply text, and never authorizes an action;
 *   - `.strict()`: unknown keys (e.g. replyText, send, execute, token) make the artifact invalid;
 *   - fields are machine-decidable; free text is not allowed.
 * `subject` is the join key: (platform, externalEventId) = the native id that also keys the Action Ledger.
 */
export const RELATIONSHIP_PAYLOAD_VERSION = 1 as const

export const RELATIONSHIP_STAGES = ['unknown', 'discovered', 'interested', 'following', 'engaged', 'recognized', 'conversation', 'relationship'] as const
export const RELATIONSHIP_PRIORITIES = ['low', 'normal', 'high'] as const
export const RECOMMENDED_HANDLING = ['reply', 'reply_later', 'no_reply', 'human_review', 'unknown'] as const
export const RELATIONSHIP_REASON_CODES = [
  'repeat-interaction',
  'high-match',
  'low-match',
  'new-contact',
  'no-candidate-match',
  'mission-aligned',
  'stage-advanced-recently',
  'dormant',
  'insufficient-data',
] as const

export const RelationshipEnrichmentPayloadSchema = z
  .object({
    subject: z.object({
      platform: z.enum(ACTION_PLATFORMS),
      /** Native event id (same value My-SNS exposes as externalEventId). */
      externalEventId: z.string().regex(/^[A-Za-z0-9._\-=]{1,200}$/),
    }),
    /** SNS-providers' candidate id (opaque). Absent when the contact matches no known candidate. */
    candidateRef: OpaqueIdSchema.optional(),
    relationshipStage: z.enum(RELATIONSHIP_STAGES),
    /** 0..1, or null when unknown. Never a made-up default. */
    relationshipValue: z.number().min(0).max(1).nullable(),
    priority: z.enum(RELATIONSHIP_PRIORITIES),
    recommendedHandling: z.enum(RECOMMENDED_HANDLING),
    reasonCodes: z.array(z.enum(RELATIONSHIP_REASON_CODES)).max(8),
    interactionCount: z.number().int().nonnegative().optional(),
    generatedAt: IsoTimestampSchema,
    analyzer: z.object({ name: z.string().max(64), version: z.string().max(32) }),
  })
  .strict()
export type RelationshipEnrichmentPayload = z.infer<typeof RelationshipEnrichmentPayloadSchema>

/** GET {sns-providers}/api/service/v1/relationship-enrichment — read-only, read-scoped token. */
export const RelationshipEnrichmentReportSchema = z.object({
  contractVersion: z.literal(1),
  service: z.literal('sns-providers'),
  generatedAt: IsoTimestampSchema,
  artifacts: z.array(ArtifactEnvelopeSchema).max(200),
  /**
   * true when the producer had more events than it enriched (its per-report cap). Optional for older producers: absent means
   * "not reported", which a consumer must NOT read as "complete".
   */
  truncated: z.boolean().optional(),
  hasMore: z.boolean().optional(),
})
export type RelationshipEnrichmentReport = z.infer<typeof RelationshipEnrichmentReportSchema>

/** Accepts only well-formed, correctly-attributed enrichment; everything else is dropped (and counted). */
export function acceptEnrichmentArtifacts(artifacts: readonly unknown[]): { accepted: { artifactId: string; payload: RelationshipEnrichmentPayload }[]; rejected: number } {
  const accepted: { artifactId: string; payload: RelationshipEnrichmentPayload }[] = []
  let rejected = 0
  for (const a of artifacts) {
    const env = ArtifactEnvelopeSchema.safeParse(a)
    if (!env.success || env.data.kind !== 'RelationshipEnrichmentArtifact' || env.data.producer !== 'sns-providers' || env.data.payloadVersion !== RELATIONSHIP_PAYLOAD_VERSION) {
      rejected++
      continue
    }
    const p = RelationshipEnrichmentPayloadSchema.safeParse(env.data.payload)
    if (!p.success) {
      rejected++
      continue
    }
    accepted.push({ artifactId: env.data.artifactId, payload: p.data })
  }
  return { accepted, rejected }
}
