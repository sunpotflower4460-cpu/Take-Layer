import { type AssetRef, AssetRefSchema } from '../core/asset.js'
import { type Clock, type IdGenerator, type SourceRef, randomIdGenerator, systemClock } from '../core/common.js'
import { type Goal, GoalSchema, type NewGoalInput, NewGoalInputSchema, pickCurrentGoal } from '../core/goal.js'
import { IdentityGraph, type LinkEvidenceKind } from '../core/identity.js'
import { type Release, ReleaseSchema, type ReleaseStatus, canTransitionRelease, releaseRefOf } from '../core/release.js'
import { type TraceContext, TraceLog } from '../core/trace.js'
import { ActionLedger } from '../ledger/action-ledger.js'
import { MemoryLedgerStorage } from '../ledger/memory-storage.js'
import type { LedgerStorage } from '../ledger/storage.js'
import { MacJobQueue, type QueueOptions } from '../runner/queue.js'
import type { EnqueueResult, JobQueue } from '../runner/queue-port.js'
import type { JobType } from '../runner/job.js'
import { type DomainStore, MemoryDomainStore } from '../store/domain-store.js'
import { FileBackedLedgerStorage, FileDomainStore, type JsonStateFile, StateFileMacJobStore, emptyState } from '../store/file-store.js'

export interface WorkspaceOptions extends QueueOptions {
  workspaceRef: string
  /** Local-development persistence (one JSON file). Ignored for any store you pass explicitly. */
  file?: JsonStateFile
  /** Override the Action Ledger store (Postgres in production). */
  ledgerStorage?: LedgerStorage
  /** Override the Mac job queue (Postgres in production). */
  queue?: JobQueue
  /** Override the domain store: Goal / Release / IdentityLink / AssetRef / OperationTrace (Postgres in production). */
  domain?: DomainStore
}

/**
 * Application service for what Artist OS actually owns. Everything else is a projection.
 * All persistence goes through Storage Ports (DomainStore, LedgerStorage, JobQueue): the same rules run on memory,
 * a JSON file (development) and Postgres (production).
 */
export class Workspace {
  readonly workspaceRef: string
  readonly domain: DomainStore
  readonly ledger: ActionLedger
  readonly trace: TraceLog
  readonly queue: JobQueue
  private readonly clock: Clock
  private readonly ids: IdGenerator

  constructor(opts: WorkspaceOptions) {
    this.workspaceRef = opts.workspaceRef
    this.clock = opts.clock ?? systemClock
    this.ids = opts.ids ?? randomIdGenerator
    const state = opts.file ? opts.file.load() : emptyState()
    this.domain = opts.domain ?? (opts.file ? new FileDomainStore(opts.file, state) : new MemoryDomainStore())
    this.trace = new TraceLog(this.domain.trace, this.clock, this.ids)
    this.ledger = new ActionLedger(opts.ledgerStorage ?? (opts.file ? new FileBackedLedgerStorage(opts.file, state) : new MemoryLedgerStorage()), { clock: this.clock })
    this.queue =
      opts.queue ??
      new MacJobQueue(opts.file ? new StateFileMacJobStore(opts.file, state) : undefined, { clock: this.clock, ids: this.ids, runnerTtlMs: opts.runnerTtlMs, durable: Boolean(opts.file), leaseMsOverride: opts.leaseMsOverride })
  }

  // ---- Goal ----
  async createGoal(input: NewGoalInput): Promise<Goal> {
    const parsed = NewGoalInputSchema.parse({ ...input, workspaceRef: this.workspaceRef })
    const now = this.clock().toISOString()
    const goal = GoalSchema.parse({ schemaVersion: 1, goalId: this.ids('goal'), status: 'active', createdAt: now, updatedAt: now, objective: '', constraints: [], ...parsed })
    await this.domain.putGoal(goal)
    return goal
  }
  goals(): Promise<Goal[]> {
    return this.domain.goals(this.workspaceRef)
  }
  async currentGoal(): Promise<Goal | undefined> {
    return pickCurrentGoal(await this.goals())
  }

  // ---- Release ----
  async createRelease(input: { title: string; releaseDate?: string; goalId?: string; isrc?: string }): Promise<Release> {
    if (input.goalId && !(await this.goals()).some((g) => g.goalId === input.goalId)) throw new Error(`unknown goal ${input.goalId}`)
    const now = this.clock().toISOString()
    const release = ReleaseSchema.parse({ schemaVersion: 1, releaseId: this.ids('rel'), workspaceRef: this.workspaceRef, status: 'planning', createdAt: now, updatedAt: now, ...input })
    await this.domain.putRelease(release)
    return release
  }
  releases(): Promise<Release[]> {
    return this.domain.releases(this.workspaceRef)
  }
  async release(releaseId: string): Promise<Release | undefined> {
    const r = await this.domain.getRelease(releaseId)
    return r && r.workspaceRef === this.workspaceRef ? r : undefined
  }
  async transitionRelease(releaseId: string, to: ReleaseStatus): Promise<Release> {
    const r = await this.release(releaseId)
    if (!r) throw new Error(`unknown release ${releaseId}`)
    if (!canTransitionRelease(r.status, to)) throw new Error(`illegal release transition ${r.status} → ${to}`)
    const next = ReleaseSchema.parse({ ...r, status: to, updatedAt: this.clock().toISOString() })
    await this.domain.putRelease(next)
    return next
  }

  // ---- Identity (links hang off a Release) ----
  private graphOver(links: readonly unknown[]): IdentityGraph {
    const g = new IdentityGraph({ clock: this.clock, ids: this.ids })
    g.restore(links)
    return g
  }
  /** A read-only graph snapshot (for dashboards). */
  async identityGraph(): Promise<IdentityGraph> {
    return this.graphOver(await this.domain.links())
  }
  async proposeReleaseLink(releaseId: string, target: SourceRef, evidence: LinkEvidenceKind, confidence: number, note?: string) {
    const r = await this.release(releaseId)
    if (!r) throw new Error(`unknown release ${releaseId}`)
    return this.domain.withLinks((links) => {
      const link = this.graphOver(links).propose({ artistOsRef: releaseRefOf(r), target, evidence, confidence, note })
      return { changed: [link], result: link }
    })
  }
  confirmLink(linkId: string, actor: { kind: 'human' | 'system'; id: string }) {
    return this.domain.withLinks((links) => {
      const l = this.graphOver(links).confirm(linkId, actor)
      return { changed: [l], result: l }
    })
  }
  rejectLink(linkId: string) {
    return this.domain.withLinks((links) => {
      const l = this.graphOver(links).reject(linkId)
      return { changed: [l], result: l }
    })
  }
  revokeLink(linkId: string) {
    return this.domain.withLinks((links) => {
      const l = this.graphOver(links).revoke(linkId)
      return { changed: [l], result: l }
    })
  }

  // ---- AssetRef ----
  async registerAsset(ref: AssetRef): Promise<AssetRef> {
    const a = AssetRefSchema.parse(ref)
    await this.domain.putAsset(a)
    return a
  }

  // ---- Release → media request → Mac job → artifact (one trace) ----
  /**
   * Requests Mac work for a Release and ties the whole story to ONE trace:
   *   release.media_requested ──(causation)──▶ mac_job.queued ──▶ (runner) mac_job.completed|failed
   * The job carries traceId + causationId, so a later reader can answer "why does this artifact exist?".
   */
  async requestMediaJob(releaseId: string, jobType: JobType, input: { inputAssetRefs?: AssetRef[]; parameters?: Record<string, never> | Record<string, unknown>; subjectRefs?: SourceRef[]; idempotencyKey?: string }, cause?: TraceContext): Promise<{ result: EnqueueResult; trace: TraceContext }> {
    const release = await this.release(releaseId)
    if (!release) throw new Error(`unknown release ${releaseId}`)
    const relRef = releaseRefOf(release)
    const ctx = cause ?? this.trace.newContext()
    const requested = await this.trace.record(ctx, { eventType: 'release.media_requested', producer: 'artist-os', workspaceRef: this.workspaceRef, subjectRefs: [relRef], summary: `${jobType} requested for release ${release.title}`, payload: { jobType } })
    const result = await this.queue.enqueue({
      jobType,
      workspaceRef: this.workspaceRef,
      subjectRefs: [relRef, ...(input.subjectRefs ?? [])],
      inputAssetRefs: input.inputAssetRefs ?? [],
      parameters: (input.parameters ?? {}) as never,
      idempotencyKey: input.idempotencyKey,
      traceId: requested.event.traceId,
      causationId: requested.event.eventId,
    })
    if (!result.ok) {
      await this.trace.record(requested.next, { eventType: 'mac_job.rejected', producer: 'artist-os', workspaceRef: this.workspaceRef, subjectRefs: [relRef], summary: `${jobType} not queued: ${result.reason}` })
      return { result, trace: requested.next }
    }
    const queued = await this.trace.record(requested.next, { eventType: 'mac_job.queued', producer: 'artist-os', workspaceRef: this.workspaceRef, subjectRefs: [relRef, { system: 'mac-runner', entityType: 'mac_job', entityId: result.job.jobId }], summary: `${jobType} queued` })
    return { result, trace: queued.next }
  }

  /** Records the outcome of a Mac job on its trace (called when the Runner reports a terminal state). */
  async recordJobOutcome(jobId: string): Promise<void> {
    const job = await this.queue.get(jobId)
    if (!job?.traceId || (job.status !== 'COMPLETED' && job.status !== 'FAILED')) return
    const existing = (await this.trace.byTrace(job.traceId)).some((e) => e.eventType.startsWith('mac_job.') && e.subjectRefs.some((r) => r.entityId === jobId) && (e.eventType === 'mac_job.completed' || e.eventType === 'mac_job.failed'))
    if (existing) return // idempotent: a retried report must not duplicate the trace
    // The outcome is caused by the QUEUED event if we can find it (so the chain is request → queued → outcome).
    const events = await this.trace.byTrace(job.traceId)
    const queued = events.find((e) => e.eventType === 'mac_job.queued' && e.subjectRefs.some((r) => r.entityId === jobId))
    await this.trace.record(
      { traceId: job.traceId, correlationId: queued?.correlationId ?? this.ids('cor'), causationId: queued?.eventId ?? job.causationId },
      {
        eventType: job.status === 'COMPLETED' ? 'mac_job.completed' : 'mac_job.failed',
        producer: 'mac-runner',
        workspaceRef: this.workspaceRef,
        subjectRefs: [{ system: 'mac-runner', entityType: 'mac_job', entityId: jobId }, ...job.resultArtifacts.map((a) => ({ system: 'mac-runner' as const, entityType: 'artifact', entityId: a.artifactId }))],
        summary: job.status === 'COMPLETED' ? `${job.jobType} completed (attempt ${job.attempt})` : `${job.jobType} failed: ${job.error?.code ?? 'unknown'}`,
      },
    )
  }
}
