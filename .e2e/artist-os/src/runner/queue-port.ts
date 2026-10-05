import type { SourceRef } from '../core/common.js'
import type { StoreInfo } from '../ledger/storage.js'
import type { ExpiryDisposition, RunnerPatch } from './queue-logic.js'
import type { JobStatus, MacJob, ReconcileOutcome, RunnerHeartbeat } from './job.js'

export type EnqueueInput = Omit<Partial<MacJob>, 'status' | 'jobId' | 'createdAt' | 'attempt'> & Pick<MacJob, 'jobType' | 'workspaceRef'>

export type EnqueueResult =
  | { ok: true; job: MacJob; deduplicated: boolean }
  | { ok: false; reason: 'no_capable_runner' | 'runner_offline' | 'invalid'; detail: string }

export interface JobAttempt {
  jobId: string
  attempt: number
  runnerId: string
  claimedAt: string
  endedAt?: string
  endReason?: 'completed' | 'failed' | 'lease_expired' | 'cancelled' | 'blocked'
}

export interface ExpiryEvent {
  jobId: string
  disposition: ExpiryDisposition
}

export type RunnerState = RunnerHeartbeat & { online: boolean; lastSeenAt: string }

/**
 * The Mac job queue port. Two implementations share the lifecycle rules in queue-logic.ts:
 *   MacJobQueue          in-memory / JSON-file: development and tests
 *   PostgresMacJobQueue  production: transactional, `FOR UPDATE SKIP LOCKED` claim, leases, attempts
 * Which one may run in production is decided by the Store Policy via `info`.
 */
export interface JobQueue {
  readonly info: StoreInfo
  heartbeat(raw: unknown): Promise<RunnerHeartbeat>
  runnerStates(): Promise<RunnerState[]>
  enqueue(input: EnqueueInput): Promise<EnqueueResult>
  claim(runnerId: string): Promise<MacJob | undefined>
  update(jobId: string, runnerId: string, patch: RunnerPatch): Promise<MacJob>
  cancel(jobId: string): Promise<MacJob>
  resolve(jobId: string, req: { action: 'requeue' | 'fail'; evidence: string }): Promise<MacJob>
  /** Operator asks the Runner that held a BLOCKED local-write job to LOOK at what exists on the Mac. Idempotent. */
  requestReconcile(jobId: string): Promise<MacJob>
  /** The Runner picks up a reconcile request addressed to it (the job's former runner only). */
  claimReconcile(runnerId: string): Promise<MacJob | undefined>
  /** completed → COMPLETED (needs the verified artifact) · not_completed → QUEUED · ambiguous → stays BLOCKED. Evidence required. */
  completeReconcile(jobId: string, runnerId: string, report: { outcome: ReconcileOutcome; evidence: string; resultArtifacts?: MacJob['resultArtifacts'] }): Promise<MacJob>
  /** Applies lease/queue expiry. Called by claim() and by a periodic maintenance tick. */
  reclaimExpired(): Promise<ExpiryEvent[]>
  get(jobId: string): Promise<MacJob | undefined>
  list(filter?: { status?: JobStatus; subject?: SourceRef }): Promise<MacJob[]>
  attempts(jobId: string): Promise<JobAttempt[]>
}
