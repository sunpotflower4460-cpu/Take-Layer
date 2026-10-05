import { type AssetRef, AssetRefSchema } from '../core/asset.js'
import { type Goal } from '../core/goal.js'
import { type IdentityLink } from '../core/identity.js'
import { type Release } from '../core/release.js'
import { MemoryTraceStore, type TraceStore } from '../core/trace.js'
import type { StoreInfo } from '../ledger/storage.js'

/**
 * Storage Port for the entities Artist OS itself owns: Goal, Release, IdentityLink, AssetRef, OperationTrace.
 * Implementations: memory (tests), JSON file (local development), Postgres (production). The domain RULES live in
 * core/* and are applied by Workspace; a store only persists validated records and, for identity links, offers one
 * exclusive section (`withLinks`) so concurrent confirmations cannot race.
 */
export interface DomainStore {
  readonly info: StoreInfo
  readonly trace: TraceStore
  goals(workspaceRef: string): Promise<Goal[]>
  putGoal(goal: Goal): Promise<void>
  releases(workspaceRef: string): Promise<Release[]>
  getRelease(releaseId: string): Promise<Release | undefined>
  putRelease(release: Release): Promise<void>
  /** Exclusive section over the identity links: `fn` sees all links and returns the ones it changed. */
  withLinks<T>(fn: (links: IdentityLink[]) => { changed: IdentityLink[]; result: T }): Promise<T>
  links(): Promise<IdentityLink[]>
  putAsset(ref: AssetRef): Promise<void>
  getAsset(assetRef: string): Promise<AssetRef | undefined>
  listAssets(filter?: { ownerSystem?: string; contentHash?: string }): Promise<AssetRef[]>
}

export class MemoryDomainStore implements DomainStore {
  readonly info: StoreInfo = { kind: 'memory', durable: false, atomicReservation: true, multiProcessSafe: false }
  readonly trace: TraceStore = new MemoryTraceStore()
  protected goalMap = new Map<string, Goal>()
  protected releaseMap = new Map<string, Release>()
  protected linkMap = new Map<string, IdentityLink>()
  protected assetMap = new Map<string, AssetRef>()
  /** Hook for the file-backed subclass. */
  protected afterWrite(): void {}

  async goals(ws: string) {
    return [...this.goalMap.values()].filter((g) => g.workspaceRef === ws)
  }
  async putGoal(g: Goal) {
    this.goalMap.set(g.goalId, g)
    this.afterWrite()
  }
  async releases(ws: string) {
    return [...this.releaseMap.values()].filter((r) => r.workspaceRef === ws)
  }
  async getRelease(id: string) {
    return this.releaseMap.get(id)
  }
  async putRelease(r: Release) {
    this.releaseMap.set(r.releaseId, r)
    this.afterWrite()
  }
  async withLinks<T>(fn: (links: IdentityLink[]) => { changed: IdentityLink[]; result: T }): Promise<T> {
    const out = fn([...this.linkMap.values()]) // synchronous: atomic within this process
    for (const l of out.changed) this.linkMap.set(l.linkId, l)
    if (out.changed.length) this.afterWrite()
    return out.result
  }
  async links() {
    return [...this.linkMap.values()]
  }
  async putAsset(ref: AssetRef) {
    // Re-validate on the way in: a runner-local ref must never carry a filesystem path.
    this.assetMap.set(ref.assetRef, AssetRefSchema.parse(ref))
    this.afterWrite()
  }
  async getAsset(id: string) {
    return this.assetMap.get(id)
  }
  async listAssets(f: { ownerSystem?: string; contentHash?: string } = {}) {
    return [...this.assetMap.values()].filter((a) => (!f.ownerSystem || a.ownerSystem === f.ownerSystem) && (!f.contentHash || a.contentHash === f.contentHash))
  }

  snapshot() {
    return { goals: [...this.goalMap.values()], releases: [...this.releaseMap.values()], links: [...this.linkMap.values()], assets: [...this.assetMap.values()] }
  }
  restore(s: { goals: Goal[]; releases: Release[]; links: IdentityLink[]; assets: AssetRef[] }) {
    this.goalMap = new Map(s.goals.map((g) => [g.goalId, g]))
    this.releaseMap = new Map(s.releases.map((r) => [r.releaseId, r]))
    this.linkMap = new Map(s.links.map((l) => [l.linkId, l]))
    this.assetMap = new Map(s.assets.map((a) => [a.assetRef, a]))
  }
}
