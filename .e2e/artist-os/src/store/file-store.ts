import { mkdirSync, readFileSync, renameSync, writeFileSync, existsSync } from 'node:fs'
import { dirname } from 'node:path'
import { z } from 'zod'
import { AssetRefSchema } from '../core/asset.js'
import { type Goal, GoalSchema } from '../core/goal.js'
import { TraceEventSchema, type TraceEvent, type TraceStore } from '../core/trace.js'
import { MemoryDomainStore } from './domain-store.js'
import { IdentityLinkSchema } from '../core/identity.js'
import { type Release, ReleaseSchema } from '../core/release.js'
import { type MacJob, MacJobSchema } from '../runner/job.js'
import type { MacJobStore } from '../runner/queue.js'
import { MemoryLedgerStorage } from '../ledger/memory-storage.js'
import type { ActionRow } from '../ledger/state-machine.js'
import type { StoreInfo } from '../ledger/storage.js'

const ActionRowSchema = z.custom<ActionRow>((v) => {
  const r = v as Partial<ActionRow> | null
  return !!r && typeof r.actionKey === 'string' && typeof r.ownerSystem === 'string' && typeof r.state === 'string' && typeof r.reservationToken === 'string' && typeof r.version === 'number'
})

/**
 * Local single-process persistence: one JSON file, written atomically (write temp + rename).
 * It makes Goal/Release/links/claims/Mac jobs survive restarts and Runner-offline periods
 * on a single machine. It is NOT a multi-writer database: production deployments should
 * use the Postgres schema in db/migrations behind the same store interfaces.
 */
export const StateFileSchema = z.object({
  schemaVersion: z.literal(1),
  goals: z.array(GoalSchema).default([]),
  releases: z.array(ReleaseSchema).default([]),
  links: z.array(IdentityLinkSchema).default([]),
  /** Dev-only persistence of the Action Ledger (see store-policy: refused for production coordination). */
  actionLedger: z.array(ActionRowSchema).default([]),
  assets: z.array(AssetRefSchema).default([]),
  traceEvents: z.array(TraceEventSchema).default([]),
  jobs: z.array(MacJobSchema).default([]),
})
export type StateFile = z.infer<typeof StateFileSchema>

export const emptyState = (): StateFile => ({ schemaVersion: 1, goals: [], releases: [], links: [], actionLedger: [], assets: [], traceEvents: [], jobs: [] })

export class JsonStateFile {
  constructor(private readonly path: string) {}

  load(): StateFile {
    if (!existsSync(this.path)) return emptyState()
    // A corrupt or future-version file throws: never silently start empty over real data.
    return StateFileSchema.parse(JSON.parse(readFileSync(this.path, 'utf8')))
  }

  save(state: StateFile): void {
    mkdirSync(dirname(this.path), { recursive: true })
    const tmp = `${this.path}.${process.pid}.tmp`
    writeFileSync(tmp, JSON.stringify(StateFileSchema.parse(state), null, 2), { mode: 0o600 })
    renameSync(tmp, this.path)
  }
}

/** Mac job store backed by the shared state file: every write persists, so queued jobs survive a restart. */
export class StateFileMacJobStore implements MacJobStore {
  constructor(private readonly file: JsonStateFile, private readonly state: StateFile) {}
  get(jobId: string): MacJob | undefined {
    return this.state.jobs.find((j) => j.jobId === jobId)
  }
  put(job: MacJob): void {
    const i = this.state.jobs.findIndex((j) => j.jobId === job.jobId)
    if (i >= 0) this.state.jobs[i] = job
    else this.state.jobs.push(job)
    this.file.save(this.state)
  }
  list(): MacJob[] {
    return [...this.state.jobs]
  }
}

export type { Goal, Release }

/**
 * Action Ledger for LOCAL DEVELOPMENT: the in-process atomic section plus a JSON file so rows survive
 * a restart. It is single-process by construction, therefore the Store Policy refuses it for
 * production cross-system write coordination.
 */
export class FileBackedLedgerStorage extends MemoryLedgerStorage {
  override readonly info: StoreInfo = { kind: 'json-file', durable: true, atomicReservation: true, multiProcessSafe: false }
  constructor(private readonly file: JsonStateFile, private readonly state: StateFile) {
    super()
    this.restore(state.actionLedger as ActionRow[])
  }
  protected override afterWrite(): void {
    this.state.actionLedger = this.snapshot()
    this.file.save(this.state)
  }
}

/** JSON-file domain store for LOCAL development: the in-process store plus a file so everything survives a restart. */
export class FileDomainStore extends MemoryDomainStore {
  override readonly info: StoreInfo = { kind: 'json-file', durable: true, atomicReservation: true, multiProcessSafe: false }
  override readonly trace: TraceStore
  constructor(private readonly file: JsonStateFile, private readonly state: StateFile) {
    super()
    this.restore({ goals: state.goals, releases: state.releases, links: state.links as never, assets: state.assets })
    const events = [...state.traceEvents]
    const save = () => {
      this.state.traceEvents = events
      this.file.save(this.state)
    }
    this.trace = {
      async append(e: TraceEvent) {
        if (events.some((x) => x.eventId === e.eventId)) throw new Error(`trace event ${e.eventId} already exists (the trace is append-only)`)
        events.push(e)
        save()
      },
      async get(id: string) {
        return events.find((e) => e.eventId === id)
      },
      async byTrace(traceId: string) {
        return events.filter((e) => e.traceId === traceId)
      },
      async all(limit = 1000) {
        return events.slice(-limit)
      },
    }
  }
  protected override afterWrite(): void {
    const s = this.snapshot()
    this.state.goals = s.goals
    this.state.releases = s.releases
    this.state.links = s.links as never
    this.state.assets = s.assets
    this.file.save(this.state)
  }
}
