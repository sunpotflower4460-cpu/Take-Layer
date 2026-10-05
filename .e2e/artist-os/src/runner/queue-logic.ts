import { type MacJob, MacJobSchema, JOB_REQUIREMENTS, type JobStatus, type ReconcileOutcome, TERMINAL_JOB_STATUSES, type JobType, type RunnerHeartbeat, canTransitionJob } from './job.js'
import { metaFor } from './job-meta.js'

/**
 * Queue rules as PURE functions. The in-memory and Postgres queues both call these inside their own atomic
 * section (single-threaded step / row lock), so there is exactly one definition of the lifecycle.
 */
export class QueueError extends Error {
  constructor(
    readonly code: 'NOT_FOUND' | 'NOT_RECONCILABLE' | 'NOT_CLAIMANT' | 'STALE_ATTEMPT' | 'ILLEGAL_TRANSITION' | 'NO_RESULT' | 'NO_ERROR' | 'WRONG_STATE' | 'EVIDENCE_REQUIRED',
    message: string,
  ) {
    super(message)
    this.name = 'QueueError'
  }
}

const iso = (d: Date) => d.toISOString()
const plus = (d: Date, ms: number) => new Date(d.getTime() + ms)
export const IN_FLIGHT: ReadonlySet<JobStatus> = new Set(['CLAIMED', 'PREPARING', 'RUNNING', 'VERIFYING'])

/** A Runner may take a job type only if it reports a real handler AND every capability the type needs. */
export function runnerSupports(hb: Pick<RunnerHeartbeat, 'supportedJobTypes' | 'capabilities' | 'status'>, jobType: JobType): boolean {
  if (hb.status === 'draining') return false
  return hb.supportedJobTypes.includes(jobType) && JOB_REQUIREMENTS[jobType].every((c) => hb.capabilities[c])
}

export function applyClaim(job: MacJob, runnerId: string, now: Date): MacJob {
  const meta = metaFor(job.jobType)
  return {
    ...job,
    status: 'CLAIMED',
    runnerId,
    claimedAt: iso(now),
    heartbeatAt: iso(now),
    leaseExpiresAt: iso(plus(now, meta.leaseMs)),
    attempt: job.attempt + 1,
    maxAttempts: Math.min(job.maxAttempts, Math.max(job.maxAttempts, 1)),
    blockedReason: undefined,
    reconcile: undefined,
  }
}

export interface RunnerPatch {
  attempt?: number
  status?: JobStatus
  progress?: number
  currentStage?: string
  error?: MacJob['error']
  resultArtifactRefs?: MacJob['resultArtifactRefs']
  resultArtifacts?: MacJob['resultArtifacts']
}

/**
 * Runner → queue update. Fenced by runnerId AND attempt: after a lease expired and the job moved on, the old
 * Runner's late report is refused. A live update extends the lease (it is the heartbeat).
 */
export function applyRunnerUpdate(job: MacJob | undefined, runnerId: string, patch: RunnerPatch, now: Date): MacJob {
  if (!job) throw new QueueError('NOT_FOUND', 'unknown job')
  if (job.runnerId !== runnerId || !IN_FLIGHT.has(job.status)) throw new QueueError('NOT_CLAIMANT', `job is not claimed by ${runnerId}`)
  if (patch.attempt !== undefined && patch.attempt !== job.attempt) throw new QueueError('STALE_ATTEMPT', 'report belongs to an earlier attempt')
  if (patch.status && patch.status !== job.status && !canTransitionJob(job.status, patch.status)) {
    throw new QueueError('ILLEGAL_TRANSITION', `illegal job transition ${job.status} → ${patch.status}`)
  }
  const status = patch.status ?? job.status
  const results = (patch.resultArtifactRefs ?? job.resultArtifactRefs).length + (patch.resultArtifacts ?? job.resultArtifacts).length
  if (status === 'COMPLETED' && results === 0) throw new QueueError('NO_RESULT', 'COMPLETED requires at least one result artifact (no fake success)')
  if (status === 'FAILED' && !(patch.error ?? job.error)) throw new QueueError('NO_ERROR', 'FAILED requires an error')
  const terminal = TERMINAL_JOB_STATUSES.has(status)
  const { attempt: _a, ...rest } = patch
  void _a
  return MacJobSchema.parse({
    ...job,
    ...rest,
    status,
    progress: status === 'COMPLETED' ? 1 : (patch.progress ?? job.progress),
    completedAt: terminal ? iso(now) : job.completedAt,
    heartbeatAt: iso(now),
    // Extend the lease only while still in flight.
    leaseExpiresAt: terminal ? job.leaseExpiresAt : iso(plus(now, metaFor(job.jobType).leaseMs)),
  })
}

export type ExpiryDisposition = 'unchanged' | 'requeued' | 'failed' | 'blocked_reconcile' | 'blocked_outcome_unknown' | 'cancelled'
export interface ExpiryResult {
  job: MacJob
  disposition: ExpiryDisposition
  /** Attempt end reason to record against the attempt that just lost its lease. */
  attemptEnd?: 'lease_expired'
}

/**
 * Lease expiry. The job is NOT handed to another Runner at the moment of the crash; it only moves once the lease
 * has run out, and then only as the job type's side-effect class allows:
 *   pure_local      → requeued (or FAILED when attempts are exhausted)
 *   local_write     → BLOCKED(LOCAL_SIDE_EFFECT_UNKNOWN): partial output may exist
 *   external_write  → BLOCKED(LEASE_EXPIRED_OUTCOME_UNKNOWN): the effect may have landed
 */
export function applyLeaseExpiry(job: MacJob, now: Date): ExpiryResult {
  if (!IN_FLIGHT.has(job.status) || !job.leaseExpiresAt || Date.parse(job.leaseExpiresAt) > now.getTime()) return { job, disposition: 'unchanged' }
  const meta = metaFor(job.jobType)
  const base = { ...job, runnerId: undefined, claimedAt: undefined, leaseExpiresAt: undefined, heartbeatAt: undefined, currentStage: undefined, progress: 0 }
  if (meta.onLeaseExpiry === 'requeue') {
    if (job.attempt >= job.maxAttempts) {
      return { job: { ...job, status: 'FAILED', completedAt: iso(now), error: { code: 'LEASE_EXPIRED', message: 'the runner stopped reporting and attempts are exhausted', retryable: false } }, disposition: 'failed', attemptEnd: 'lease_expired' }
    }
    return { job: { ...base, status: 'QUEUED' }, disposition: 'requeued', attemptEnd: 'lease_expired' }
  }
  const reconcile = meta.onLeaseExpiry === 'block_reconcile'
  return {
    job: { ...base, runnerId: job.runnerId, status: 'BLOCKED', blockedReason: reconcile ? 'LOCAL_SIDE_EFFECT_UNKNOWN' : 'LEASE_EXPIRED_OUTCOME_UNKNOWN' },
    disposition: reconcile ? 'blocked_reconcile' : 'blocked_outcome_unknown',
    attemptEnd: 'lease_expired',
  }
}

export function applyQueuedExpiry(job: MacJob, now: Date): MacJob | undefined {
  if (job.status === 'QUEUED' && job.expiresAt && Date.parse(job.expiresAt) <= now.getTime()) {
    return { ...job, status: 'CANCELLED', completedAt: iso(now), error: { code: 'EXPIRED', message: 'job expired before a runner claimed it', retryable: false } }
  }
  return undefined
}

/** Operator decision on a BLOCKED job after checking the Mac (reconcile) — never automatic. */
export function applyOperatorResolve(job: MacJob | undefined, req: { action: 'requeue' | 'fail'; evidence: string }, now: Date): MacJob {
  if (!job) throw new QueueError('NOT_FOUND', 'unknown job')
  if (job.status !== 'BLOCKED') throw new QueueError('WRONG_STATE', `only BLOCKED jobs can be resolved (job is ${job.status})`)
  if (!req.evidence.trim()) throw new QueueError('EVIDENCE_REQUIRED', 'a resolution needs evidence (what was checked)')
  if (req.action === 'requeue') return { ...job, status: 'QUEUED', runnerId: undefined, blockedReason: undefined, reconcile: undefined, progress: 0, maxAttempts: Math.max(job.maxAttempts, job.attempt + 1) }
  return { ...job, status: 'FAILED', completedAt: iso(now), error: { code: 'RECONCILED_FAILED', message: `operator: ${req.evidence.slice(0, 300)}`, retryable: false } }
}

export function applyCancel(job: MacJob | undefined, now: Date): MacJob {
  if (!job) throw new QueueError('NOT_FOUND', 'unknown job')
  if (!canTransitionJob(job.status, 'CANCELLED')) throw new QueueError('ILLEGAL_TRANSITION', `cannot cancel a ${job.status} job`)
  return { ...job, status: 'CANCELLED', completedAt: iso(now) }
}

/**
 * Reconciliation of a BLOCKED local-write job. Read-only on the Mac (the Runner LOOKS at what exists), so asking
 * twice is harmless. The job is released only by evidence:
 *   completed      the output is there and verifies  → COMPLETED (with the validated result artifact)
 *   not_completed  nothing durable was produced      → QUEUED again (a safe requeue)
 *   ambiguous      cannot tell                       → stays BLOCKED; a human decides via `resolve`
 */
export function applyReconcileRequest(job: MacJob | undefined, now: Date): MacJob {
  if (!job) throw new QueueError('NOT_FOUND', 'unknown job')
  if (job.status !== 'BLOCKED' || job.blockedReason !== 'LOCAL_SIDE_EFFECT_UNKNOWN') {
    throw new QueueError('NOT_RECONCILABLE', 'only a BLOCKED job with LOCAL_SIDE_EFFECT_UNKNOWN can be reconciled by its Runner')
  }
  if (job.reconcile && (job.reconcile.state === 'requested' || job.reconcile.state === 'in_progress')) return job // idempotent
  return { ...job, reconcile: { state: 'requested', requestedAt: iso(now), updatedAt: iso(now) } }
}

export function isReconcilableBy(job: MacJob, runnerId: string): boolean {
  return job.status === 'BLOCKED' && job.blockedReason === 'LOCAL_SIDE_EFFECT_UNKNOWN' && job.runnerId === runnerId && (job.reconcile?.state === 'requested' || job.reconcile?.state === 'in_progress')
}

export function applyReconcileClaim(job: MacJob, now: Date): MacJob {
  return { ...job, reconcile: { ...job.reconcile!, state: 'in_progress', updatedAt: iso(now) } }
}

export function applyReconcileOutcome(
  job: MacJob | undefined,
  runnerId: string,
  report: { outcome: ReconcileOutcome; evidence: string; resultArtifacts?: MacJob['resultArtifacts'] },
  now: Date,
): MacJob {
  if (!job) throw new QueueError('NOT_FOUND', 'unknown job')
  if (!isReconcilableBy(job, runnerId)) throw new QueueError('NOT_RECONCILABLE', `job is not awaiting reconciliation by ${runnerId}`)
  const evidence = report.evidence.trim()
  if (!evidence) throw new QueueError('EVIDENCE_REQUIRED', 'a reconciliation outcome needs evidence (what was checked)')
  const rec = (outcome: ReconcileOutcome, state: 'resolved' | 'ambiguous') => ({ state, outcome, evidence: evidence.slice(0, 500), requestedAt: job.reconcile!.requestedAt, updatedAt: iso(now) })
  if (report.outcome === 'ambiguous') return { ...job, reconcile: rec('ambiguous', 'ambiguous') }
  if (report.outcome === 'not_completed') {
    return { ...job, status: 'QUEUED', runnerId: undefined, blockedReason: undefined, progress: 0, maxAttempts: Math.max(job.maxAttempts, job.attempt + 1), reconcile: rec('not_completed', 'resolved') }
  }
  if (!report.resultArtifacts?.length) throw new QueueError('NO_RESULT', 'a "completed" reconciliation must carry the verified result artifact (no fake success)')
  return { ...job, status: 'COMPLETED', blockedReason: undefined, progress: 1, completedAt: iso(now), error: undefined, resultArtifacts: report.resultArtifacts, reconcile: rec('completed', 'resolved') }
}
