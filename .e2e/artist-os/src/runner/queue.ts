import { type Clock, type IdGenerator, type SourceRef, randomIdGenerator, sourceRefKey, systemClock } from '../core/common.js'
import type { StoreInfo } from '../ledger/storage.js'
import { type JobStatus, type MacJob, type ReconcileOutcome, MacJobSchema, RunnerHeartbeatSchema, type RunnerHeartbeat, assertNoCommandParameters } from './job.js'
import { metaFor } from './job-meta.js'
import { type RunnerPatch, QueueError, applyCancel, applyClaim, applyLeaseExpiry, applyOperatorResolve, applyQueuedExpiry, applyReconcileClaim, applyReconcileOutcome, applyReconcileRequest, isReconcilableBy, applyRunnerUpdate, runnerSupports } from './queue-logic.js'
import type { EnqueueInput, EnqueueResult, ExpiryEvent, JobAttempt, JobQueue, RunnerState } from './queue-port.js'

export type { EnqueueResult } from './queue-port.js'

export interface MacJobStore {
  get(jobId: string): MacJob | undefined
  put(job: MacJob): void
  list(): MacJob[]
}
/** Dev/test store. */
export class MemoryMacJobStore implements MacJobStore {
  private readonly jobs = new Map<string, MacJob>()
  get = (id: string) => this.jobs.get(id)
  put = (j: MacJob) => void this.jobs.set(j.jobId, j)
  list = () => [...this.jobs.values()]
}

export interface QueueOptions {
  clock?: Clock
  ids?: IdGenerator
  /** A runner with no heartbeat for this long is considered offline. */
  runnerTtlMs?: number
  /** Override every job type's lease (tests). */
  leaseMsOverride?: number
}

/**
 * In-memory / JSON-file queue (development and tests). Same lifecycle as production because it calls the same
 * pure rules; it is single-process by construction, so the Store Policy refuses it for production Mac jobs.
 */
export class MacJobQueue implements JobQueue {
  readonly info: StoreInfo
  private readonly runners = new Map<string, { hb: RunnerHeartbeat; seenAt: number }>()
  private readonly attemptLog: JobAttempt[] = []
  private readonly clock: Clock
  private readonly ids: IdGenerator
  private readonly runnerTtlMs: number

  constructor(
    private readonly store: MacJobStore = new MemoryMacJobStore(),
    private readonly opts: QueueOptions & { durable?: boolean } = {},
  ) {
    this.clock = opts.clock ?? systemClock
    this.ids = opts.ids ?? randomIdGenerator
    this.runnerTtlMs = opts.runnerTtlMs ?? 90_000
    this.info = { kind: opts.durable ? 'json-file' : 'memory', durable: Boolean(opts.durable), atomicReservation: true, multiProcessSafe: false }
  }

  private lease(job: MacJob): MacJob {
    // test hook: shorten leases without changing production metadata
    return this.opts.leaseMsOverride && job.leaseExpiresAt ? { ...job, leaseExpiresAt: new Date(Date.parse(job.claimedAt ?? job.leaseExpiresAt) + this.opts.leaseMsOverride).toISOString() } : job
  }

  async heartbeat(raw: unknown): Promise<RunnerHeartbeat> {
    const hb = RunnerHeartbeatSchema.parse(raw)
    this.runners.set(hb.runnerId, { hb, seenAt: this.clock().getTime() })
    return hb
  }

  async runnerStates(): Promise<RunnerState[]> {
    const now = this.clock().getTime()
    return [...this.runners.values()].map(({ hb, seenAt }) => ({ ...hb, online: now - seenAt <= this.runnerTtlMs, lastSeenAt: new Date(seenAt).toISOString() }))
  }

  async enqueue(input: EnqueueInput): Promise<EnqueueResult> {
    try {
      assertNoCommandParameters(input.parameters ?? {})
    } catch (e) {
      return { ok: false, reason: 'invalid', detail: (e as Error).message }
    }
    if (input.idempotencyKey) {
      const dupe = this.store.list().find((j) => j.idempotencyKey === input.idempotencyKey && j.workspaceRef === input.workspaceRef)
      if (dupe) return { ok: true, job: dupe, deduplicated: true }
    }
    // Capability discovery: never queue work for a capability no known Runner has ever reported.
    if (this.runners.size > 0 && ![...this.runners.values()].some(({ hb }) => runnerSupports({ ...hb, status: 'idle' }, input.jobType))) {
      return { ok: false, reason: 'no_capable_runner', detail: `no registered runner supports ${input.jobType}` }
    }
    const parsed = MacJobSchema.safeParse({
      maxAttempts: metaFor(input.jobType).maxAttempts,
      ...input,
      schemaVersion: 1,
      jobId: this.ids('job'),
      status: 'QUEUED',
      createdAt: this.clock().toISOString(),
      attempt: 0,
    })
    if (!parsed.success) return { ok: false, reason: 'invalid', detail: parsed.error.issues[0]?.message ?? 'invalid job' }
    this.store.put(parsed.data)
    return { ok: true, job: parsed.data, deduplicated: false }
  }

  async claim(runnerId: string): Promise<MacJob | undefined> {
    const entry = this.runners.get(runnerId)
    if (!entry) return undefined // an unknown runner must heartbeat first
    await this.reclaimExpired()
    const now = this.clock()
    const job = this.store
      .list()
      .filter((j) => j.status === 'QUEUED' && runnerSupports(entry.hb, j.jobType))
      .sort((a, b) => b.priority - a.priority || a.createdAt.localeCompare(b.createdAt))[0]
    if (!job) return undefined
    const claimed = this.lease(applyClaim(job, runnerId, now))
    this.store.put(claimed)
    this.attemptLog.push({ jobId: job.jobId, attempt: claimed.attempt, runnerId, claimedAt: now.toISOString() })
    return claimed
  }

  async update(jobId: string, runnerId: string, patch: RunnerPatch): Promise<MacJob> {
    await this.reclaimExpired()
    const next = this.lease(applyRunnerUpdate(this.store.get(jobId), runnerId, patch, this.clock()))
    this.store.put(next)
    if (next.status === 'COMPLETED' || next.status === 'FAILED') this.endAttempt(jobId, next.attempt, next.status === 'COMPLETED' ? 'completed' : 'failed')
    return next
  }

  async cancel(jobId: string): Promise<MacJob> {
    const next = applyCancel(this.store.get(jobId), this.clock())
    this.store.put(next)
    this.endAttempt(jobId, next.attempt, 'cancelled')
    return next
  }

  async resolve(jobId: string, req: { action: 'requeue' | 'fail'; evidence: string }): Promise<MacJob> {
    const next = applyOperatorResolve(this.store.get(jobId), req, this.clock())
    this.store.put(next)
    return next
  }

  async requestReconcile(jobId: string): Promise<MacJob> {
    const next = applyReconcileRequest(this.store.get(jobId), this.clock())
    this.store.put(next)
    return next
  }

  async claimReconcile(runnerId: string): Promise<MacJob | undefined> {
    const job = this.store.list().find((j) => isReconcilableBy(j, runnerId))
    if (!job) return undefined
    const next = applyReconcileClaim(job, this.clock())
    this.store.put(next)
    return next
  }

  async completeReconcile(jobId: string, runnerId: string, report: { outcome: ReconcileOutcome; evidence: string; resultArtifacts?: MacJob['resultArtifacts'] }): Promise<MacJob> {
    const next = applyReconcileOutcome(this.store.get(jobId), runnerId, report, this.clock())
    this.store.put(next)
    if (next.status === 'COMPLETED') this.endAttempt(jobId, next.attempt, 'completed')
    return next
  }

  async reclaimExpired(): Promise<ExpiryEvent[]> {
    const now = this.clock()
    const events: ExpiryEvent[] = []
    for (const j of this.store.list()) {
      const q = applyQueuedExpiry(j, now)
      if (q) {
        this.store.put(q)
        events.push({ jobId: j.jobId, disposition: 'cancelled' })
        continue
      }
      const r = applyLeaseExpiry(j, now)
      if (r.disposition === 'unchanged') continue
      this.store.put(r.job)
      this.endAttempt(j.jobId, j.attempt, 'lease_expired')
      events.push({ jobId: j.jobId, disposition: r.disposition })
    }
    return events
  }

  async get(jobId: string) {
    return this.store.get(jobId)
  }

  async list(filter: { status?: JobStatus; subject?: SourceRef } = {}) {
    return this.store.list().filter((j) => (!filter.status || j.status === filter.status) && (!filter.subject || j.subjectRefs.some((r) => sourceRefKey(r) === sourceRefKey(filter.subject!))))
  }

  async attempts(jobId: string) {
    return this.attemptLog.filter((a) => a.jobId === jobId)
  }

  private endAttempt(jobId: string, attempt: number, reason: NonNullable<JobAttempt['endReason']>): void {
    const a = this.attemptLog.find((x) => x.jobId === jobId && x.attempt === attempt && !x.endedAt)
    if (a) {
      a.endedAt = this.clock().toISOString()
      a.endReason = reason
    }
  }
}

export { QueueError }
