import type { Pool } from 'pg'
import { type AssetRef, AssetRefSchema } from '../core/asset.js'
import { type Goal, GoalSchema } from '../core/goal.js'
import { type IdentityLink, IdentityLinkSchema } from '../core/identity.js'
import { type Release, ReleaseSchema } from '../core/release.js'
import { sourceRefKey } from '../core/common.js'
import { type TraceEvent, TraceEventSchema, type TraceStore } from '../core/trace.js'
import type { StoreInfo } from '../ledger/storage.js'
import type { DomainStore } from './domain-store.js'

class PostgresTraceStore implements TraceStore {
  constructor(private readonly pool: Pool) {}
  async append(e: TraceEvent) {
    await this.pool.query('INSERT INTO artist_os_trace_events (event_id, trace_id, correlation_id, causation_id, event_type, producer, workspace_ref, occurred_at, data) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)', [
      e.eventId, e.traceId, e.correlationId, e.causationId ?? null, e.eventType, e.producer, e.workspaceRef, e.occurredAt, JSON.stringify(e),
    ])
  }
  async get(id: string) {
    const r = await this.pool.query('SELECT data FROM artist_os_trace_events WHERE event_id = $1', [id])
    return r.rows[0] ? TraceEventSchema.parse(r.rows[0].data) : undefined
  }
  async byTrace(traceId: string) {
    const r = await this.pool.query('SELECT data FROM artist_os_trace_events WHERE trace_id = $1 ORDER BY occurred_at, event_id', [traceId])
    return r.rows.map((x) => TraceEventSchema.parse(x.data))
  }
  async all(limit = 1000) {
    const r = await this.pool.query('SELECT data FROM artist_os_trace_events ORDER BY occurred_at DESC LIMIT $1', [limit])
    return r.rows.map((x) => TraceEventSchema.parse(x.data)).reverse()
  }
}

/** Production domain store. Records are re-validated on every read so a bad row fails loudly instead of leaking into logic. */
export class PostgresDomainStore implements DomainStore {
  readonly info: StoreInfo = { kind: 'postgres', durable: true, atomicReservation: true, multiProcessSafe: true }
  readonly trace: TraceStore
  constructor(private readonly pool: Pool) {
    this.trace = new PostgresTraceStore(pool)
  }

  async goals(ws: string): Promise<Goal[]> {
    const r = await this.pool.query('SELECT data FROM artist_os_goals WHERE workspace_ref = $1 ORDER BY updated_at DESC', [ws])
    return r.rows.map((x) => GoalSchema.parse(x.data))
  }
  async putGoal(g: Goal) {
    await this.pool.query(
      `INSERT INTO artist_os_goals (goal_id, workspace_ref, status, priority, data, updated_at) VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (goal_id) DO UPDATE SET status=$3, priority=$4, data=$5, updated_at=$6`,
      [g.goalId, g.workspaceRef, g.status, g.priority, JSON.stringify(g), g.updatedAt],
    )
  }
  async releases(ws: string): Promise<Release[]> {
    const r = await this.pool.query('SELECT data FROM artist_os_releases WHERE workspace_ref = $1 ORDER BY updated_at DESC', [ws])
    return r.rows.map((x) => ReleaseSchema.parse(x.data))
  }
  async getRelease(id: string) {
    const r = await this.pool.query('SELECT data FROM artist_os_releases WHERE release_id = $1', [id])
    return r.rows[0] ? ReleaseSchema.parse(r.rows[0].data) : undefined
  }
  async putRelease(rel: Release) {
    await this.pool.query(
      `INSERT INTO artist_os_releases (release_id, workspace_ref, status, data, updated_at) VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (release_id) DO UPDATE SET status=$3, data=$4, updated_at=$5`,
      [rel.releaseId, rel.workspaceRef, rel.status, JSON.stringify(rel), rel.updatedAt],
    )
  }

  async links(): Promise<IdentityLink[]> {
    const r = await this.pool.query('SELECT data FROM artist_os_identity_links ORDER BY updated_at')
    return r.rows.map((x) => IdentityLinkSchema.parse(x.data))
  }

  async withLinks<T>(fn: (links: IdentityLink[]) => { changed: IdentityLink[]; result: T }): Promise<T> {
    const c = await this.pool.connect()
    try {
      await c.query('BEGIN')
      // One exclusive section for identity changes: confirmations of different links of the same entity cannot interleave.
      await c.query("SELECT pg_advisory_xact_lock(hashtextextended('artist_os_identity_links', 0))")
      const cur = await c.query('SELECT data FROM artist_os_identity_links')
      const out = fn(cur.rows.map((x) => IdentityLinkSchema.parse(x.data)))
      for (const l of out.changed) {
        await c.query(
          `INSERT INTO artist_os_identity_links (link_id, artist_os_key, target_key, target_system, target_type, status, evidence, data, updated_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8, now())
           ON CONFLICT (link_id) DO UPDATE SET status=$6, data=$8, updated_at=now()`,
          [l.linkId, sourceRefKey(l.artistOsRef), sourceRefKey(l.target), l.target.system, l.target.entityType, l.status, l.evidence, JSON.stringify(l)],
        )
      }
      await c.query('COMMIT')
      return out.result
    } catch (e) {
      await c.query('ROLLBACK').catch(() => undefined)
      throw e
    } finally {
      c.release()
    }
  }

  async putAsset(ref: AssetRef) {
    const a = AssetRefSchema.parse(ref)
    await this.pool.query(
      `INSERT INTO artist_os_asset_refs (asset_ref, owner_system, kind, location_type, runner_id, content_hash, data, created_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (asset_ref) DO UPDATE SET data=$7, content_hash=$6`,
      [a.assetRef, a.ownerSystem, a.kind, a.locationType, a.runnerId ?? null, a.contentHash ?? null, JSON.stringify(a), a.createdAt],
    )
  }
  async getAsset(id: string) {
    const r = await this.pool.query('SELECT data FROM artist_os_asset_refs WHERE asset_ref = $1', [id])
    return r.rows[0] ? AssetRefSchema.parse(r.rows[0].data) : undefined
  }
  async listAssets(f: { ownerSystem?: string; contentHash?: string } = {}) {
    const r = await this.pool.query('SELECT data FROM artist_os_asset_refs WHERE ($1::text IS NULL OR owner_system = $1) AND ($2::text IS NULL OR content_hash = $2) ORDER BY created_at DESC LIMIT 1000', [f.ownerSystem ?? null, f.contentHash ?? null])
    return r.rows.map((x) => AssetRefSchema.parse(x.data))
  }
}
