import { z } from 'zod'
import { IsoTimestampSchema, OpaqueIdSchema, SystemIdSchema } from '../core/common.js'

/**
 * Artist OS ↔ specialist read contract, v1.
 *
 * Artist OS DEFINES this contract; specialist repos adopt it additively
 * (a read-only, service-token-authenticated endpoint). Specialists remain the
 * source of truth: everything here is a projection, and every attention item
 * names the specialist's own approval/action target.
 */
export const SERVICE_CONTRACT_VERSION = 1 as const

export const SERVICE_HEALTH_STATES = ['healthy', 'degraded', 'unavailable'] as const

/** GET {baseUrl}/api/service/health — no auth required, no secrets, no tenant data. */
export const ServiceHealthSchema = z.object({
  contractVersion: z.literal(SERVICE_CONTRACT_VERSION),
  service: SystemIdSchema,
  version: z.string().max(64),
  status: z.enum(SERVICE_HEALTH_STATES),
  degradedReason: z.string().max(300).optional(),
  /** Capability ids this service really supports right now (e.g. "inbox.read"). */
  capabilities: z.array(z.string().max(128)).max(100).default([]),
  /** Additive (managed-mode phase). Absent on older services ⇒ treated as unknown, never as managed. */
  runtimeMode: z.enum(['standalone', 'artist_os_managed']).optional(),
  modeInvalid: z.boolean().optional(),
  ownership: z
    .object({
      /** true ⇒ this system can execute external replies to inbound events right now. */
      inboundReplyExecution: z.union([z.boolean(), z.record(z.string(), z.boolean())]).optional(),
      canonicalMetaWebhookReceiver: z.boolean().optional(),
      recommendation: z.boolean().optional(),
      relationshipIntelligence: z.boolean().optional(),
      proactiveEngagement: z.boolean().optional(),
    })
    .optional(),
  checkedAt: IsoTimestampSchema,
})
export type ServiceHealth = z.infer<typeof ServiceHealthSchema>

export const ATTENTION_KINDS = [
  'approval', // a human decision gates a specialist action
  'failure', // something failed and needs a human
  'auth', // credential/connection needs a human
  'ambiguity', // low confidence / conflict
  'policy', // a policy restriction blocks progress
  'handoff', // unsupported-by-API action the human must do manually
] as const

/**
 * Where a human acts. Artist OS never records approval itself.
 * `endpoint` = Artist OS may forward the approve/reject to the specialist;
 * `deeplink` = the specialist requires its own authenticated UI/session
 * (e.g. My-SNS approvals need a human session, so Artist OS links out).
 */
export const ActionTargetSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('deeplink'),
    url: z.url(),
  }),
  z.object({
    type: z.literal('endpoint'),
    method: z.enum(['POST', 'PUT', 'PATCH']),
    url: z.url(),
    /** Opaque id the specialist expects back so a stale approval can be refused (optimistic binding). */
    bindingToken: z.string().max(512).optional(),
  }),
])
export type ActionTarget = z.infer<typeof ActionTargetSchema>

export const PRIORITIES = ['low', 'normal', 'high', 'urgent'] as const

export const AttentionItemSchema = z.object({
  sourceSystem: SystemIdSchema,
  sourceEntityId: OpaqueIdSchema,
  sourceEntityType: z.string().max(64),
  kind: z.enum(ATTENTION_KINDS),
  summary: z.string().max(300),
  priority: z.enum(PRIORITIES).default('normal'),
  createdAt: IsoTimestampSchema,
  dueAt: IsoTimestampSchema.optional(),
  /** Absent when no machine action exists: then the item is informational / human-only. */
  action: ActionTargetSchema.optional(),
})
export type AttentionItem = z.infer<typeof AttentionItemSchema>

export const ACTIVITY_STATES = ['completed', 'running', 'scheduled'] as const

export const ActivityItemSchema = z.object({
  sourceSystem: SystemIdSchema,
  sourceEntityId: OpaqueIdSchema,
  sourceEntityType: z.string().max(64),
  state: z.enum(ACTIVITY_STATES),
  summary: z.string().max(300),
  progress: z.number().min(0).max(1).optional(),
  at: IsoTimestampSchema,
})
export type ActivityItem = z.infer<typeof ActivityItemSchema>

/** GET {baseUrl}/api/service/v1/status — service-token authenticated, read-only, no-store. */
export const ServiceStatusReportSchema = z.object({
  contractVersion: z.literal(SERVICE_CONTRACT_VERSION),
  service: SystemIdSchema,
  generatedAt: IsoTimestampSchema,
  attention: z.array(AttentionItemSchema).max(500).default([]),
  activity: z.array(ActivityItemSchema).max(500).default([]),
  /** Optional specialist-specific counters for dashboards; opaque to Artist OS logic. */
  counters: z.record(z.string(), z.number()).default({}),
})
export type ServiceStatusReport = z.infer<typeof ServiceStatusReportSchema>
