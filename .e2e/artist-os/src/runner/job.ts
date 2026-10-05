import { z } from 'zod'
import {
  AssetRefSchema,
} from '../core/asset.js'
import { ArtifactEnvelopeSchema } from '../artifacts/pipeline.js'
import { IsoTimestampSchema, OpaqueIdSchema, SCHEMA_VERSION, SourceRefSchema } from '../core/common.js'

/**
 * Typed Mac Job contract. There is deliberately NO free-form command field:
 * a job is {jobType + schema-validated parameters}; the Runner executes only
 * handlers it has registered for that type. No arbitrary remote shell, ever.
 */
export const JOB_TYPES = [
  'MEDIA_ANALYSIS',
  'VIDEO_ANALYSIS',
  'AUDIO_ANALYSIS',
  'SONG_RESOLUTION',
  'LYRICS_ALIGNMENT',
  'GENERATE_EDIT_PROPOSALS',
  'RENDER_EDIT_PLAN',
  'MEDIA_QUALITY_GATE',
  'GENERATE_SHORT_VARIANTS',
  'EXTRACT_THUMBNAIL_CANDIDATES',
  'MUSIC_TRACK_ANALYSIS',
  /** Take-Layer's resolver calibration CLI (corpus manifest in, report out). An honest name: it is NOT per-song resolution. */
  'RESOLVER_CALIBRATION',
] as const
export type JobType = (typeof JOB_TYPES)[number]

export const JOB_STATUSES = ['QUEUED', 'CLAIMED', 'PREPARING', 'RUNNING', 'VERIFYING', 'COMPLETED', 'FAILED', 'BLOCKED', 'CANCELLED'] as const
export type JobStatus = (typeof JOB_STATUSES)[number]
export const TERMINAL_JOB_STATUSES: ReadonlySet<JobStatus> = new Set(['COMPLETED', 'FAILED', 'CANCELLED'])

/** Runner capability flags reported via heartbeat. */
export const RUNNER_CAPABILITIES = ['takeLayer', 'vision', 'whisper', 'audioAnalysis', 'videoRender', 'localAI', 'songResolution', 'videoAnalysis', 'renderEditPlan', 'resolverCalibration'] as const
export type RunnerCapability = (typeof RUNNER_CAPABILITIES)[number]

/**
 * Which Runner capabilities each job type needs. A job is never offered to a
 * Runner lacking any of them. Handlers that don't exist yet are listed in
 * IMPLEMENTED_JOB_TYPES = [] and so fail closed as `unsupported`.
 */
export const JOB_REQUIREMENTS: Record<JobType, readonly RunnerCapability[]> = {
  MEDIA_ANALYSIS: ['audioAnalysis'],
  VIDEO_ANALYSIS: ['videoAnalysis'],
  AUDIO_ANALYSIS: ['audioAnalysis'],
  SONG_RESOLUTION: ['songResolution'],
  LYRICS_ALIGNMENT: ['whisper'],
  GENERATE_EDIT_PROPOSALS: ['takeLayer', 'vision'],
  RENDER_EDIT_PLAN: ['renderEditPlan'],
  MEDIA_QUALITY_GATE: ['takeLayer', 'videoRender'],
  GENERATE_SHORT_VARIANTS: ['takeLayer', 'videoRender'],
  EXTRACT_THUMBNAIL_CANDIDATES: ['videoRender'],
  MUSIC_TRACK_ANALYSIS: ['audioAnalysis'],
  RESOLVER_CALIBRATION: ['resolverCalibration'],
}

export const BLOCKED_REASONS = ['LOCAL_SIDE_EFFECT_UNKNOWN', 'LEASE_EXPIRED_OUTCOME_UNKNOWN'] as const
export type BlockedReason = (typeof BLOCKED_REASONS)[number]

export const RECONCILE_OUTCOMES = ['completed', 'not_completed', 'ambiguous'] as const
export type ReconcileOutcome = (typeof RECONCILE_OUTCOMES)[number]

/** requested → in_progress (a Runner took it) → resolved | ambiguous. `ambiguous` keeps the job BLOCKED. */
export const ReconcileStateSchema = z.object({
  state: z.enum(['requested', 'in_progress', 'ambiguous', 'resolved']),
  requestedAt: IsoTimestampSchema,
  updatedAt: IsoTimestampSchema,
  outcome: z.enum(RECONCILE_OUTCOMES).optional(),
  /** What the Runner/operator actually checked (short, path-free). */
  evidence: z.string().max(500).optional(),
})
export type ReconcileState = z.infer<typeof ReconcileStateSchema>

export const JobErrorSchema = z.object({
  code: z.string().max(64),
  message: z.string().max(500),
  retryable: z.boolean(),
})

export const MacJobSchema = z.object({
  schemaVersion: z.literal(SCHEMA_VERSION),
  jobId: OpaqueIdSchema,
  workspaceRef: OpaqueIdSchema,
  jobType: z.enum(JOB_TYPES),
  subjectRefs: z.array(SourceRefSchema).max(20).default([]),
  inputAssetRefs: z.array(AssetRefSchema).max(50).default([]),
  /** Validated per jobType by the handler's own schema; must be plain JSON data, never commands. */
  parameters: z.record(z.string(), z.json()).default({}),
  priority: z.number().int().min(0).max(100).default(50),
  status: z.enum(JOB_STATUSES),
  runnerId: OpaqueIdSchema.optional(),
  progress: z.number().min(0).max(1).default(0),
  currentStage: z.string().max(128).optional(),
  createdAt: IsoTimestampSchema,
  expiresAt: IsoTimestampSchema.optional(),
  claimedAt: IsoTimestampSchema.optional(),
  completedAt: IsoTimestampSchema.optional(),
  resultArtifactRefs: z.array(AssetRefSchema).max(50).default([]),
  /** Small typed results delivered inline (measurements, never media). Validated per job type before acceptance. */
  resultArtifacts: z.array(ArtifactEnvelopeSchema).max(10).default([]),
  error: JobErrorSchema.optional(),
  attempt: z.number().int().min(0).default(0),
  /** Lease: the claim is valid until this instant and is extended by the claiming Runner's progress/heartbeat updates. */
  leaseExpiresAt: IsoTimestampSchema.optional(),
  heartbeatAt: IsoTimestampSchema.optional(),
  /**
   * Why a BLOCKED job is blocked (a lease expired on a job whose side effects make an automatic retry unsafe).
   *  LOCAL_SIDE_EFFECT_UNKNOWN  a local file may have been (partially) written on the Mac: the Runner can check by looking
   *  LEASE_EXPIRED_OUTCOME_UNKNOWN  something outside the Mac may have changed: only a human with evidence decides
   */
  blockedReason: z.enum(BLOCKED_REASONS).optional(),
  /** Runner-side reconciliation of a BLOCKED local-write job (see queue-logic applyReconcile*). Never a blind success/failure choice. */
  reconcile: ReconcileStateSchema.optional(),
  maxAttempts: z.number().int().min(1).max(10).default(3),
  /** Caller-supplied key so retries of the same request never create a second job. */
  idempotencyKey: z.string().max(128).optional(),
  traceId: OpaqueIdSchema.optional(),
  causationId: OpaqueIdSchema.optional(),
})
export type MacJob = z.infer<typeof MacJobSchema>

/** Parameter keys that smell like command execution are rejected outright. */
const FORBIDDEN_PARAMETER_KEYS = /^(cmd|command|shell|script|exec|args|argv|bash|sh|powershell)$/i
export function assertNoCommandParameters(parameters: Record<string, unknown>): void {
  const walk = (v: unknown, path: string): void => {
    if (v && typeof v === 'object') {
      for (const [k, child] of Object.entries(v)) {
        if (FORBIDDEN_PARAMETER_KEYS.test(k)) throw new Error(`parameter "${path}${k}" looks like a command; typed jobs only`)
        walk(child, `${path}${k}.`)
      }
    }
  }
  walk(parameters, '')
}

const ALLOWED_TRANSITIONS: Record<JobStatus, readonly JobStatus[]> = {
  QUEUED: ['CLAIMED', 'CANCELLED', 'BLOCKED'],
  CLAIMED: ['PREPARING', 'RUNNING', 'QUEUED', 'FAILED', 'CANCELLED'], // QUEUED: claim lease expired / released
  PREPARING: ['RUNNING', 'FAILED', 'CANCELLED', 'BLOCKED'],
  RUNNING: ['VERIFYING', 'COMPLETED', 'FAILED', 'CANCELLED', 'BLOCKED'],
  VERIFYING: ['COMPLETED', 'FAILED', 'CANCELLED'],
  BLOCKED: ['QUEUED', 'CANCELLED'],
  COMPLETED: [],
  FAILED: [],
  CANCELLED: [],
}
export const canTransitionJob = (from: JobStatus, to: JobStatus) => ALLOWED_TRANSITIONS[from].includes(to)

/** Heartbeat payload from a Runner. The Runner reports itself; Artist OS never reaches into the Mac. */
export const RunnerHeartbeatSchema = z.object({
  runnerId: OpaqueIdSchema,
  architecture: z.string().max(32),
  status: z.enum(['idle', 'busy', 'draining']),
  capabilities: z.object(Object.fromEntries(RUNNER_CAPABILITIES.map((c) => [c, z.boolean().default(false)])) as Record<RunnerCapability, z.ZodDefault<z.ZodBoolean>>),
  /** Job types this Runner build actually has handlers for (stubs are NOT listed). */
  supportedJobTypes: z.array(z.enum(JOB_TYPES)).max(JOB_TYPES.length).default([]),
  version: z.string().max(64).optional(),
  sentAt: IsoTimestampSchema,
})
export type RunnerHeartbeat = z.infer<typeof RunnerHeartbeatSchema>
