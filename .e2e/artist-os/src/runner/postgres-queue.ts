import type { Pool, PoolClient } from 'pg'
import { type Clock, type IdGenerator, type SourceRef, randomIdGenerator, systemClock } from '../core/common.js'
import type { StoreInfo } from '../ledger/storage.js'
import { type JobStatus, type MacJob, type ReconcileOutcome, MacJobSchema, RunnerHeartbeatSchema, type RunnerHeartbeat, assertNoCommandParameters } from './job.js'
import { metaFor } from './job-meta.js'
import { type RunnerPatch, applyCancel, applyLeaseExpiry, applyOperatorResolve, applyReconcileClaim, applyReconcileOutcome, applyReconcileRequest, isReconcilableBy, applyQueuedExpiry, applyRunnerUpdate, runnerSupports } from './queue-logic.js'
import type { EnqueueInput, EnqueueResult, ExpiryEvent, JobAttempt, JobQueue, RunnerState } from './queue-port.js'

const iso = (v: unknown) => (v == null ? undefined : new Date(v as string | Date).toISOString())
/** Key-order-independent JSON (Postgres jsonb does not preserve key order). */
const canon = (v: unknown): string => JSON.stringify(v, (_k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b))) : x))
const clean = <T extends Record<string, unknown>>(o: T): T => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)) as T

function fromDb(r: Record<string, unknown>): MacJob {
  return MacJobSchema.parse(
    clean({
      schemaVersion: 1,
      jobId: r.job_id,
      workspaceRef: r.workspace_ref,
      jobType: r.job_type,
      subjectRefs: r.subject_refs,
      inputAssetRefs: r.input_asset_refs,
      parameters: r.parameters,
      priority: r.priority,
      status: r.status,
      runnerId: r.runner_id ?? undefined,
      progress: r.progress,
      currentStage: r.current_stage ?? undefined,
      createdAt: iso(r.created_at),
      expiresAt: iso(r.expires_at),
      claimedAt: iso(r.claimed_at),
      heartbeatAt: iso(r.heartbeat_at),
      leaseExpiresAt: iso(r.lease_expires_at),
      completedAt: iso(r.completed_at),
      resultArtifacts: r.result_artifacts,
      error: r.error ?? undefined,
      blockedReason: r.blocked_reason ?? undefined,
      reconcile: r.reconcile ?? undefined,
      attempt: r.attempt,
      maxAttempts: r.max_attempts,
      idempotencyKey: r.idempotency_key ?? undefined,
      traceId: r.trace_id ?? undefined,
      causationId: r.causation_id ?? undefined,
    }),
  )
}

const COLS = `job_id, workspace_ref, job_type, status, priority, subject_refs, input_asset_refs, parameters, progress, current_stage, runner_id, attempt, max_attempts,
  created_at, expires_at, claimed_at, heartbeat_at, lease_expires_at, completed_at, error, blocked_reason, idempotency_key, trace_id, causation_id, result_artifacts, updated_at, reconcile`

function params(j: MacJob, now: Date): unknown[] {
  return [
    j.jobId, j.workspaceRef, j.jobType, j.status, j.priority, JSON.stringify(j.subjectRefs), JSON.stringify(j.inputAssetRefs), JSON.stringify(j.parameters), j.progress,
    j.currentStage ?? null, j.runnerId ?? null, j.attempt, j.maxAttempts, j.createdAt, j.expiresAt ?? null, j.claimedAt ?? null, j.heartbeatAt ?? null, j.leaseExpiresAt ?? null,
    j.completedAt ?? null, j.error ? JSON.stringify(j.error) : null, j.blockedReason ?? null, j.idempotencyKey ?? null, j.traceId ?? null, j.causationId ?? null,
    JSON.stringify(j.resultArtifacts), now.toISOString(), j.reconcile ? JSON.stringify(j.reconcile) : null,
  ]
}

export interface PostgresQueueOptions {
  clock?: Clock
  ids?: IdGenerator
  runnerTtlMs?: number
}

/**
 * Production Mac job queue on Postgres.
 *  - claim is ONE atomic statement: `UPDATE … FROM (SELECT … FOR UPDATE SKIP LOCKED LIMIT 1)`, so any number of
 *    Runners / Artist OS processes can race and exactly one gets a given job, and none blocks on another's row lock;
 *  - leases, attempts and runner capability history are persisted;
 *  - lifecycle rules are the shared pure functions in queue-logic.ts (same as the in-memory queue);
 *  - DB CHECK constraints refuse impossible rows (in flight without a lease, FAILED without an error, …).
 */
export class PostgresMacJobQueue implements JobQueue {
  readonly info: StoreInfo = { kind: 'postgres', durable: true, atomicReservation: true, multiProcessSafe: true }
  private readonly clock: Clock
  private readonly ids: IdGenerator
  private readonly runnerTtlMs: number
  constructor(private readonly pool: Pool, opts: PostgresQueueOptions = {}) {
    this.clock = opts.clock ?? systemClock
    this.ids = opts.ids ?? randomIdGenerator
    this.runnerTtlMs = opts.runnerTtlMs ?? 90_000
  }

  private async tx<T>(fn: (c: PoolClient) => Promise<T>): Promise<T> {
    const c = await this.pool.connect()
    try {
      await c.query('BEGIN')
      const out = await fn(c)
      await c.query('COMMIT')
      return out
    } catch (e) {
      await c.query('ROLLBACK').catch(() => undefined)
      throw e
    } finally {
      c.release()
    }
  }

  async heartbeat(raw: unknown): Promise<RunnerHeartbeat> {
    const hb = RunnerHeartbeatSchema.parse(raw)
    const now = this.clock()
    await this.tx(async (c) => {
      const prev = await c.query('SELECT capabilities, supported_job_types FROM artist_os_mac_runners WHERE runner_id = $1 FOR UPDATE', [hb.runnerId])
      const caps = JSON.stringify(hb.capabilities)
      const types = [...hb.supportedJobTypes].sort()
      await c.query(
        `INSERT INTO artist_os_mac_runners (runner_id, architecture, status, capabilities, supported_job_types, version, first_seen_at, last_seen_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$7)
         ON CONFLICT (runner_id) DO UPDATE SET architecture=$2, status=$3, capabilities=$4, supported_job_types=$5, version=$6, last_seen_at=$7`,
        [hb.runnerId, hb.architecture, hb.status, caps, types, hb.version ?? null, now.toISOString()],
      )
      const changed = !prev.rows[0] || canon(prev.rows[0].capabilities) !== canon(hb.capabilities) || [...prev.rows[0].supported_job_types].sort().join() !== types.join()
      if (changed) await c.query('INSERT INTO artist_os_mac_runner_snapshots (runner_id, at, capabilities, supported_job_types) VALUES ($1,$2,$3,$4)', [hb.runnerId, now.toISOString(), caps, types])
    })
    return hb
  }

  private rowToHeartbeat(r: Record<string, unknown>): RunnerHeartbeat {
    return RunnerHeartbeatSchema.parse({ runnerId: r.runner_id, architecture: r.architecture, status: r.status, capabilities: r.capabilities, supportedJobTypes: r.supported_job_types, version: r.version ?? undefined, sentAt: iso(r.last_seen_at) })
  }

  async runnerStates(): Promise<RunnerState[]> {
    const now = this.clock().getTime()
    const r = await this.pool.query('SELECT * FROM artist_os_mac_runners ORDER BY runner_id')
    return r.rows.map((row) => {
      const seen = new Date(row.last_seen_at).getTime()
      return { ...this.rowToHeartbeat(row), online: now - seen <= this.runnerTtlMs, lastSeenAt: new Date(seen).toISOString() }
    })
  }

  async enqueue(input: EnqueueInput): Promise<EnqueueResult> {
    try {
      assertNoCommandParameters(input.parameters ?? {})
    } catch (e) {
      return { ok: false, reason: 'invalid', detail: (e as Error).message }
    }
    const runners = (await this.pool.query('SELECT * FROM artist_os_mac_runners')).rows.map((r) => this.rowToHeartbeat(r))
    if (runners.length > 0 && !runners.some((hb) => runnerSupports({ ...hb, status: 'idle' }, input.jobType))) {
      return { ok: false, reason: 'no_capable_runner', detail: `no registered runner supports ${input.jobType}` }
    }
    const now = this.clock()
    const parsed = MacJobSchema.safeParse({ maxAttempts: metaFor(input.jobType).maxAttempts, ...input, schemaVersion: 1, jobId: this.ids('job'), status: 'QUEUED', createdAt: now.toISOString(), attempt: 0 })
    if (!parsed.success) return { ok: false, reason: 'invalid', detail: parsed.error.issues[0]?.message ?? 'invalid job' }
    const job = parsed.data
    const ins = await this.pool.query(
      `INSERT INTO artist_os_mac_jobs (${COLS}) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27)
       ON CONFLICT (workspace_ref, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING RETURNING job_id`,
      params(job, now),
    )
    if (ins.rowCount === 1) return { ok: true, job, deduplicated: false }
    const dupe = await this.pool.query('SELECT * FROM artist_os_mac_jobs WHERE workspace_ref = $1 AND idempotency_key = $2', [job.workspaceRef, job.idempotencyKey])
    return { ok: true, job: fromDb(dupe.rows[0]), deduplicated: true }
  }

  async claim(runnerId: string): Promise<MacJob | undefined> {
    await this.reclaimExpired()
    const now = this.clock()
    const rr = await this.pool.query('SELECT * FROM artist_os_mac_runners WHERE runner_id = $1', [runnerId])
    if (!rr.rows[0]) return undefined // must heartbeat first
    const hb = this.rowToHeartbeat(rr.rows[0])
    const types = (hb.supportedJobTypes as string[]).filter((t) => runnerSupports(hb, t as never))
    if (types.length === 0) return undefined
    return this.tx(async (c) => {
      // Atomic claim: the locked subselect skips rows another transaction holds, the UPDATE applies the lease.
      const leaseByType = types.map((t) => `WHEN '${t}' THEN ${Number(metaFor(t as never).leaseMs)}`).join(' ')
      const r = await c.query(
        `WITH picked AS (
           SELECT job_id FROM artist_os_mac_jobs
           WHERE status = 'QUEUED' AND job_type = ANY($1::text[]) AND (expires_at IS NULL OR expires_at > $3)
           ORDER BY priority DESC, created_at ASC
           FOR UPDATE SKIP LOCKED LIMIT 1)
         UPDATE artist_os_mac_jobs j
            SET status='CLAIMED', runner_id=$2, claimed_at=$3, heartbeat_at=$3,
                lease_expires_at = $3::timestamptz + ((CASE j.job_type ${leaseByType} ELSE 600000 END) * interval '1 millisecond'),
                attempt = j.attempt + 1, blocked_reason = NULL, updated_at = $3
           FROM picked WHERE j.job_id = picked.job_id
         RETURNING j.*`,
        [types, runnerId, now.toISOString()],
      )
      if (r.rowCount === 0) return undefined
      const job = fromDb(r.rows[0])
      await c.query('INSERT INTO artist_os_mac_job_attempts (job_id, attempt, runner_id, claimed_at) VALUES ($1,$2,$3,$4)', [job.jobId, job.attempt, runnerId, now.toISOString()])
      return job
    })
  }

  private async lockJob(c: PoolClient, jobId: string): Promise<MacJob | undefined> {
    const r = await c.query('SELECT * FROM artist_os_mac_jobs WHERE job_id = $1 FOR UPDATE', [jobId])
    return r.rows[0] ? fromDb(r.rows[0]) : undefined
  }

  private async save(c: PoolClient, job: MacJob, now: Date): Promise<void> {
    await c.query(
      `UPDATE artist_os_mac_jobs SET workspace_ref=$2, job_type=$3, status=$4, priority=$5, subject_refs=$6, input_asset_refs=$7, parameters=$8, progress=$9, current_stage=$10, runner_id=$11, attempt=$12, max_attempts=$13,
         created_at=$14, expires_at=$15, claimed_at=$16, heartbeat_at=$17, lease_expires_at=$18, completed_at=$19, error=$20, blocked_reason=$21, idempotency_key=$22, trace_id=$23, causation_id=$24, result_artifacts=$25, updated_at=$26, reconcile=$27
       WHERE job_id=$1`,
      params(job, now),
    )
  }

  private async endAttempt(c: PoolClient, jobId: string, attempt: number, reason: NonNullable<JobAttempt['endReason']>, now: Date) {
    await c.query('UPDATE artist_os_mac_job_attempts SET ended_at=$4, end_reason=$3 WHERE job_id=$1 AND attempt=$2 AND ended_at IS NULL', [jobId, attempt, reason, now.toISOString()])
  }

  async update(jobId: string, runnerId: string, patch: RunnerPatch): Promise<MacJob> {
    await this.reclaimExpired()
    const now = this.clock()
    return this.tx(async (c) => {
      const next = applyRunnerUpdate(await this.lockJob(c, jobId), runnerId, patch, now)
      await this.save(c, next, now)
      if (next.status === 'COMPLETED' || next.status === 'FAILED') await this.endAttempt(c, jobId, next.attempt, next.status === 'COMPLETED' ? 'completed' : 'failed', now)
      if (next.status === 'COMPLETED') {
        for (const [i, ref] of next.resultArtifactRefs.entries()) {
          await c.query('INSERT INTO artist_os_mac_job_artifact_refs (job_id, ref_index, asset_ref) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [jobId, i, JSON.stringify(ref)])
        }
      }
      return next
    })
  }

  async cancel(jobId: string): Promise<MacJob> {
    const now = this.clock()
    return this.tx(async (c) => {
      const cur = await this.lockJob(c, jobId)
      const next = applyCancel(cur, now)
      await this.save(c, next, now)
      if (cur && cur.attempt > 0) await this.endAttempt(c, jobId, cur.attempt, 'cancelled', now)
      return next
    })
  }

  async resolve(jobId: string, req: { action: 'requeue' | 'fail'; evidence: string }): Promise<MacJob> {
    const now = this.clock()
    return this.tx(async (c) => {
      const next = applyOperatorResolve(await this.lockJob(c, jobId), req, now)
      await this.save(c, next, now)
      return next
    })
  }

  async requestReconcile(jobId: string): Promise<MacJob> {
    const now = this.clock()
    return this.tx(async (c) => {
      const next = applyReconcileRequest(await this.lockJob(c, jobId), now)
      await this.save(c, next, now)
      return next
    })
  }

  async claimReconcile(runnerId: string): Promise<MacJob | undefined> {
    const now = this.clock()
    return this.tx(async (c) => {
      const r = await c.query(
        `SELECT * FROM artist_os_mac_jobs WHERE status = 'BLOCKED' AND blocked_reason = 'LOCAL_SIDE_EFFECT_UNKNOWN' AND runner_id = $1
           AND reconcile->>'state' IN ('requested','in_progress') ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`,
        [runnerId],
      )
      if (!r.rows[0]) return undefined
      const job = fromDb(r.rows[0])
      if (!isReconcilableBy(job, runnerId)) return undefined
      const next = applyReconcileClaim(job, now)
      await this.save(c, next, now)
      return next
    })
  }

  async completeReconcile(jobId: string, runnerId: string, report: { outcome: ReconcileOutcome; evidence: string; resultArtifacts?: MacJob['resultArtifacts'] }): Promise<MacJob> {
    const now = this.clock()
    return this.tx(async (c) => {
      const next = applyReconcileOutcome(await this.lockJob(c, jobId), runnerId, report, now)
      await this.save(c, next, now)
      if (next.status === 'COMPLETED') await this.endAttempt(c, jobId, next.attempt, 'completed', now)
      return next
    })
  }

  async reclaimExpired(): Promise<ExpiryEvent[]> {
    const now = this.clock()
    return this.tx(async (c) => {
      const due = await c.query(
        `SELECT * FROM artist_os_mac_jobs
          WHERE (status IN ('CLAIMED','PREPARING','RUNNING','VERIFYING') AND lease_expires_at <= $1)
             OR (status = 'QUEUED' AND expires_at IS NOT NULL AND expires_at <= $1)
          FOR UPDATE SKIP LOCKED`,
        [now.toISOString()],
      )
      const events: ExpiryEvent[] = []
      for (const row of due.rows) {
        const job = fromDb(row)
        const q = applyQueuedExpiry(job, now)
        if (q) {
          await this.save(c, q, now)
          events.push({ jobId: job.jobId, disposition: 'cancelled' })
          continue
        }
        const r = applyLeaseExpiry(job, now)
        if (r.disposition === 'unchanged') continue
        await this.save(c, r.job, now)
        await this.endAttempt(c, job.jobId, job.attempt, r.disposition === 'requeued' || r.disposition === 'failed' ? 'lease_expired' : 'blocked', now)
        events.push({ jobId: job.jobId, disposition: r.disposition })
      }
      return events
    })
  }

  async get(jobId: string) {
    const r = await this.pool.query('SELECT * FROM artist_os_mac_jobs WHERE job_id = $1', [jobId])
    return r.rows[0] ? fromDb(r.rows[0]) : undefined
  }

  async list(filter: { status?: JobStatus; subject?: SourceRef } = {}) {
    const r = await this.pool.query(
      `SELECT * FROM artist_os_mac_jobs WHERE ($1::text IS NULL OR status = $1) AND ($2::jsonb IS NULL OR subject_refs @> $2::jsonb) ORDER BY created_at DESC LIMIT 500`,
      [filter.status ?? null, filter.subject ? JSON.stringify([filter.subject]) : null],
    )
    return r.rows.map(fromDb)
  }

  async attempts(jobId: string): Promise<JobAttempt[]> {
    const r = await this.pool.query('SELECT * FROM artist_os_mac_job_attempts WHERE job_id = $1 ORDER BY attempt', [jobId])
    return r.rows.map((x) => ({ jobId, attempt: x.attempt, runnerId: x.runner_id, claimedAt: iso(x.claimed_at)!, endedAt: iso(x.ended_at), endReason: x.end_reason ?? undefined }))
  }
}

