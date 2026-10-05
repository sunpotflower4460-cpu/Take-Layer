import { z } from 'zod'
import { IsoTimestampSchema, OpaqueIdSchema } from '../core/common.js'
import { ACTION_PLATFORMS } from '../ledger/action-key.js'

/**
 * Read-only inbound-event projection (contract v1), served by the canonical inbound owner (My-SNS).
 * Purpose: let relationship intelligence (SNS-providers) and Artist OS see WHAT needs a reply and WHO owns
 * it, without moving the event or sharing credentials.
 *
 * Privacy: no tokens, no raw provider payloads. Message text is exposed only for PUBLIC comments (as a
 * short excerpt); DM bodies are never exposed (`textExcerpt` is absent for dm).
 */
export const INBOUND_CONTRACT_VERSION = 1 as const
export const REPLY_STATES = ['none', 'scheduled', 'sent', 'failed', 'cancelled'] as const

export const InboundEventSchema = z.object({
  sourceSystem: z.literal('my-sns'),
  /** My-SNS inbox item id (opaque). */
  eventId: OpaqueIdSchema,
  platform: z.enum(ACTION_PLATFORMS),
  kind: z.enum(['comment', 'dm', 'mention', 'reply']),
  /** The platform-native id: the basis of the CrossSystemActionKey. */
  externalEventId: OpaqueIdSchema,
  receivedAt: IsoTimestampSchema,
  /** Join key for relationship context: (platform, externalContactId). Not a credential. */
  contactRef: z.object({ platform: z.enum(ACTION_PLATFORMS), externalContactId: z.string().max(200) }).optional(),
  authorHandle: z.string().max(100).optional(),
  textExcerpt: z.string().max(280).optional(),
  /** Related Seed id (opaque ref only). */
  seedRef: OpaqueIdSchema.optional(),
  needsAction: z.boolean(),
  replyState: z.enum(REPLY_STATES),
  ownerSystem: z.literal('my-sns'),
})
export type InboundEvent = z.infer<typeof InboundEventSchema>

export const InboundEventsReportSchema = z.object({
  contractVersion: z.literal(INBOUND_CONTRACT_VERSION),
  service: z.literal('my-sns'),
  generatedAt: IsoTimestampSchema,
  events: z.array(InboundEventSchema).max(200),
})
export type InboundEventsReport = z.infer<typeof InboundEventsReportSchema>
