import { readFileSync } from 'node:fs'
import { isAbsolute } from 'node:path'
import type { ArtifactEnvelope } from '../artifacts/pipeline.js'
import type { AssetRef } from '../core/asset.js'
import { type Clock, systemClock } from '../core/common.js'
import { HandlerError, type JobHandler, handlerFor, REGISTERED_HANDLERS } from './handlers/index.js'
import { JOB_REQUIREMENTS, type MacJob, MacJobSchema, type RunnerCapability, RUNNER_CAPABILITIES } from './job.js'

export interface RunnerTransport {
  heartbeat(hb: unknown): Promise<void>
  claim(runnerId: string): Promise<MacJob | null>
  update(jobId: string, patch: Record<string, unknown>): Promise<{ ok: boolean; status: number }>
  /** A reconcile request addressed to this Runner (a BLOCKED local-write job it used to hold), if any. */
  claimReconcile(runnerId: string): Promise<MacJob | null>
  reportReconcile(jobId: string, body: Record<string, unknown>): Promise<{ ok: boolean; status: number }>
}

/** Pull-based HTTPS transport: the Mac only makes OUTBOUND calls. No inbound port, no SSH. */
export class HttpRunnerTransport implements RunnerTransport {
  constructor(private readonly opts: { baseUrl: string; token: string; fetchImpl?: typeof fetch; timeoutMs?: number }) {}
  private async post(path: string, body: unknown) {
    const f = this.opts.fetchImpl ?? fetch
    const ctl = new AbortController()
    const t = setTimeout(() => ctl.abort(), this.opts.timeoutMs ?? 15_000)
    try {
      return await f(new URL(path, this.opts.baseUrl).toString(), { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${this.opts.token}` }, body: JSON.stringify(body), signal: ctl.signal, redirect: 'error' })
    } finally {
      clearTimeout(t)
    }
  }
  async heartbeat(hb: unknown) {
    const r = await this.post('/api/runner/heartbeat', hb)
    if (!r.ok) throw new Error(`heartbeat HTTP ${r.status}`)
  }
  async claim(runnerId: string) {
    const r = await this.post('/api/runner/claim', { runnerId })
    if (!r.ok) throw new Error(`claim HTTP ${r.status}`)
    const body = (await r.json()) as { job: unknown }
    return body.job ? MacJobSchema.parse(body.job) : null
  }
  async claimReconcile(runnerId: string) {
    const r = await this.post('/api/runner/reconcile/claim', { runnerId })
    if (!r.ok) throw new Error(`reconcile claim HTTP ${r.status}`)
    const body = (await r.json()) as { job: unknown }
    return body.job ? MacJobSchema.parse(body.job) : null
  }
  async reportReconcile(jobId: string, body: Record<string, unknown>) {
    const r = await this.post(`/api/runner/reconcile/${encodeURIComponent(jobId)}`, body)
    return { ok: r.ok, status: r.status }
  }
  async update(jobId: string, patch: Record<string, unknown>) {
    const r = await this.post(`/api/runner/jobs/${encodeURIComponent(jobId)}`, patch)
    return { ok: r.ok, status: r.status }
  }
}

/** Local registry: runner-local asset id → absolute path. Lives on the Mac; paths are never sent anywhere. */
export class LocalAssetResolver {
  private readonly map: Map<string, string>
  constructor(entries: Record<string, string>) {
    this.map = new Map()
    for (const [id, path] of Object.entries(entries)) {
      if (!isAbsolute(path)) throw new Error(`asset "${id}" must map to an absolute path`)
      this.map.set(id, path)
    }
  }
  static fromFile(file: string): LocalAssetResolver {
    return new LocalAssetResolver(JSON.parse(readFileSync(file, 'utf8')) as Record<string, string>)
  }
  resolve = (ref: AssetRef): string | undefined => this.map.get(ref.locationId)
  /** By bare asset id (e.g. a corpus root directory registered on this runner). */
  resolveAssetId = (id: string): string | undefined => this.map.get(id)
  /** Registers a file this runner just produced (e.g. a rendered MP4) under an opaque id. The path stays here. */
  register(id: string, path: string): void {
    if (!isAbsolute(path)) throw new Error(`asset "${id}" must map to an absolute path`)
    this.map.set(id, path)
  }
}

export interface RunnerOptions {
  runnerId: string
  architecture: string
  transport: RunnerTransport
  resolver: { resolve(ref: AssetRef): string | undefined }
  handlers?: readonly JobHandler[]
  version?: string
  clock?: Clock
}

export type TickResult = 'idle' | 'completed' | 'failed'

export class MacRunner {
  private readonly handlers: readonly JobHandler[]
  private readonly clock: Clock
  constructor(private readonly o: RunnerOptions) {
    this.handlers = o.handlers ?? REGISTERED_HANDLERS
    this.clock = o.clock ?? systemClock
  }

  /** Capability discovery: what this build can REALLY do. A handler's absence means the job type is not advertised. */
  heartbeatPayload(status: 'idle' | 'busy' | 'draining' = 'idle') {
    const supported = this.handlers.map((h) => h.jobType)
    // A capability is reported true ONLY because a registered handler needs it: never granted wholesale, never for a stub.
    const has = new Set<RunnerCapability>(supported.flatMap((t) => JOB_REQUIREMENTS[t]))
    return {
      runnerId: this.o.runnerId,
      architecture: this.o.architecture,
      status,
      capabilities: Object.fromEntries(RUNNER_CAPABILITIES.map((c) => [c, has.has(c)])),
      supportedJobTypes: supported,
      version: this.o.version,
      sentAt: this.clock().toISOString(),
    }
  }

  beat(status?: 'idle' | 'busy' | 'draining') {
    return this.o.transport.heartbeat(this.heartbeatPayload(status))
  }

  /** Claims at most one job and runs it to a terminal state. Never throws for a job-level failure. */
  async tick(): Promise<TickResult> {
    const job = await this.o.transport.claim(this.o.runnerId)
    if (!job) return 'idle'
    // `attempt` fences this report to the claim that produced it: after a lease expiry the old Runner's late updates are refused.
    const patch = (p: Record<string, unknown>) => this.o.transport.update(job.jobId, { runnerId: this.o.runnerId, attempt: job.attempt, ...p })
    const fail = async (code: string, message: string, retryable: boolean): Promise<TickResult> => {
      await patch({ status: 'FAILED', error: { code, message: message.slice(0, 500), retryable } })
      return 'failed'
    }

    const handler = handlerFor(job.jobType, this.handlers)
    // Unreachable through the queue (it only offers supported types) but a Runner never fakes support.
    if (!handler) return fail('UNSUPPORTED_JOB_TYPE', `${job.jobType} has no handler on this runner`, false)

    await patch({ status: 'PREPARING', currentStage: 'preparing' })
    await patch({ status: 'RUNNING', currentStage: 'running', progress: 0 })
    let artifacts: ArtifactEnvelope[]
    try {
      const out = await handler.run({
        job,
        runnerId: this.o.runnerId,
        resolveAsset: (ref) => this.o.resolver.resolve(ref),
        progress: async (fraction, stage) => void (await patch({ currentStage: stage, progress: Math.min(Math.max(fraction, 0), 0.99) }).catch(() => undefined)),
      })
      artifacts = out.artifacts
    } catch (e) {
      // Messages are written to be path-free; an unexpected error is reported generically so no local path/secret leaks.
      if (e instanceof HandlerError) return fail(e.code, e.message, e.retryable)
      return fail('HANDLER_ERROR', 'the handler failed unexpectedly', false)
    }

    await patch({ status: 'VERIFYING', currentStage: 'verifying' })
    const done = await patch({ status: 'COMPLETED', currentStage: 'done', resultArtifacts: artifacts })
    return done.ok ? 'completed' : 'failed' // a refused result (422/409) leaves the server-side job FAILED
  }

  /**
   * Answers an operator's "Request reconciliation" for a BLOCKED job this Runner used to hold. The handler LOOKS at the
   * Mac and reports completed / not_completed / ambiguous with evidence; this method never decides on its own.
   */
  async reconcileTick(): Promise<'idle' | 'reported'> {
    const job = await this.o.transport.claimReconcile(this.o.runnerId)
    if (!job) return 'idle'
    const handler = handlerFor(job.jobType, this.handlers)
    let body: Record<string, unknown>
    if (!handler?.reconcile) {
      body = { outcome: 'ambiguous', evidence: `this runner build has no reconcile logic for ${job.jobType}` }
    } else {
      try {
        const report = await handler.reconcile({ job, runnerId: this.o.runnerId, resolveAsset: (ref) => this.o.resolver.resolve(ref), progress: async () => undefined })
        body = report.outcome === 'completed' ? { outcome: 'completed', evidence: report.evidence, resultArtifacts: report.artifacts } : { outcome: report.outcome, evidence: report.evidence }
      } catch {
        body = { outcome: 'ambiguous', evidence: 'the reconcile check itself failed; nothing could be established' }
      }
    }
    await this.o.transport.reportReconcile(job.jobId, { runnerId: this.o.runnerId, ...body })
    return 'reported'
  }

  /** Drains the queue: ticks until idle. Used by the CLI loop and tests. */
  async drain(limit = 50): Promise<TickResult[]> {
    const out: TickResult[] = []
    for (let i = 0; i < limit; i++) {
      const r = await this.tick()
      if (r === 'idle') break
      out.push(r)
    }
    return out
  }
}
