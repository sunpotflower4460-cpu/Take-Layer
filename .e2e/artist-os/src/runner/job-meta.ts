import type { JobType } from './job.js'

/**
 * Side-effect classes decide what is SAFE to do when a Runner disappears mid-job.
 *
 *  pure_local       reads local inputs, writes nothing durable outside the result (analysis). Re-running is harmless.
 *  local_write      writes new local files (render output). A crash may leave partials: a human/handler must reconcile.
 *  external_write   changes something outside the Mac (upload, provider write). Outcome may have landed: never auto-retry.
 */
export const SIDE_EFFECT_CLASSES = ['pure_local', 'local_write', 'external_write'] as const
export type SideEffectClass = (typeof SIDE_EFFECT_CLASSES)[number]

/** What the queue does when the lease expires while the job is in flight. */
export type OnLeaseExpiry = 'requeue' | 'block_reconcile' | 'block_outcome_unknown'

export interface JobTypeMeta {
  sideEffectClass: SideEffectClass
  onLeaseExpiry: OnLeaseExpiry
  /** Lease granted at claim and on every progress update. */
  leaseMs: number
  maxAttempts: number
}

const MIN = 60_000
const pure = (leaseMs = 10 * MIN): JobTypeMeta => ({ sideEffectClass: 'pure_local', onLeaseExpiry: 'requeue', leaseMs, maxAttempts: 3 })
const localWrite = (leaseMs = 30 * MIN): JobTypeMeta => ({ sideEffectClass: 'local_write', onLeaseExpiry: 'block_reconcile', leaseMs, maxAttempts: 1 })

/**
 * Per-type policy (data, not logic). A type with `external_write` would use `block_outcome_unknown`
 * (none exists yet; the table forces the choice to be made when one is added).
 */
export const JOB_TYPE_META: Record<JobType, JobTypeMeta> = {
  MEDIA_ANALYSIS: pure(),
  VIDEO_ANALYSIS: pure(30 * MIN),
  AUDIO_ANALYSIS: pure(),
  SONG_RESOLUTION: pure(),
  LYRICS_ALIGNMENT: pure(30 * MIN),
  MUSIC_TRACK_ANALYSIS: pure(),
  RESOLVER_CALIBRATION: pure(60 * MIN),
  GENERATE_EDIT_PROPOSALS: pure(30 * MIN),
  MEDIA_QUALITY_GATE: pure(30 * MIN),
  RENDER_EDIT_PLAN: localWrite(),
  GENERATE_SHORT_VARIANTS: localWrite(),
  EXTRACT_THUMBNAIL_CANDIDATES: localWrite(),
}

export const metaFor = (t: JobType): JobTypeMeta => JOB_TYPE_META[t]
