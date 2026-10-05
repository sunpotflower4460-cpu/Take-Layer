import { readFileSync } from 'node:fs'
import type { Pool, PoolClient } from 'pg'
import type { ActionKey } from './action-key.js'
import type { ActionRow, LedgerState } from './state-machine.js'
import type { LedgerEvent, LedgerStorage, RowDecision, StoreInfo } from './storage.js'

const MIGRATIONS = [
  { version: 1, name: 'action_ledger', file: new URL('../../db/migrations/0001_action_ledger.sql', import.meta.url) },
  { version: 2, name: 'mac_jobs', file: new URL('../../db/migrations/0002_mac_jobs.sql', import.meta.url) },
  { version: 3, name: 'domain', file: new URL('../../db/migrations/0003_domain.sql', import.meta.url) },
  { version: 4, name: 'render_reconcile', file: new URL('../../db/migrations/0004_render_reconcile.sql', import.meta.url) },
] as const

/** Applies the (idempotent) migrations. Run explicitly (`npm run db:migrate`) or by tests; never implicitly on a request path. */
export async function applyMigrations(pool: Pool): Promise<void> {
  for (const m of MIGRATIONS) await pool.query(readFileSync(m.file, 'utf8'))
}

const iso = (v: unknown) => (v == null ? undefined : new Date(v as string | Date).toISOString())

function fromDb(r: Record<string, unknown>): ActionRow {
  return {
    actionKey: r.action_key as ActionKey,
    ownerSystem: r.owner_system as string,
    state: r.state as ActionRow['state'],
    attempt: r.attempt as number,
    reservationToken: r.reservation_token as string,
    reservedAt: iso(r.reserved_at)!,
    leaseExpiresAt: iso(r.lease_expires_at)!,
    executingAt: iso(r.executing_at),
    completedAt: iso(r.completed_at),
    outcomeRef: (r.outcome_ref as string | null) ?? undefined,
    failureCode: (r.failure_code as string | null) ?? undefined,
    unknownReason: (r.unknown_reason as string | null) ?? undefined,
    reconciliation: (r.reconciliation as ActionRow['reconciliation'] | null) ?? undefined,
    updatedAt: iso(r.updated_at)!,
    version: r.version as number,
  }
}

/**
 * Postgres-backed ledger: the production store for cross-system write coordination.
 *
 * Atomicity: every mutation runs in ONE transaction that first takes
 * `pg_advisory_xact_lock(hashtextextended(action_key))`, so concurrent reserve requests for the
 * same key (from any number of Artist OS processes) are serialized and exactly one can observe
 * "no row". The PRIMARY KEY plus an optimistic `version` check are a second line of defense: a
 * lost update raises instead of silently overwriting.
 */
export class PostgresLedgerStorage implements LedgerStorage {
  readonly info: StoreInfo = { kind: 'postgres', durable: true, atomicReservation: true, multiProcessSafe: true }
  constructor(private readonly pool: Pool) {}

  async withRow<T>(actionKey: ActionKey, decide: (existing: ActionRow | undefined) => RowDecision<T>, now: Date): Promise<T> {
    const client = await this.pool.connect()
    try {
      await client.query('BEGIN')
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [actionKey])
      const cur = await client.query('SELECT * FROM artist_os_action_ledger WHERE action_key = $1', [actionKey])
      const existing = cur.rows[0] ? fromDb(cur.rows[0]) : undefined
      const d = decide(existing)
      if (d.row) await this.write(client, d.row, existing)
      if (d.event) {
        await client.query('INSERT INTO artist_os_action_events (action_key, at, kind, actor, from_state, to_state, detail) VALUES ($1,$2,$3,$4,$5,$6,$7)', [
          actionKey,
          now.toISOString(),
          d.event.kind,
          d.event.actor,
          d.event.fromState,
          d.event.toState,
          d.event.detail ?? null,
        ])
      }
      await client.query('COMMIT')
      return d.result
    } catch (e) {
      await client.query('ROLLBACK').catch(() => undefined)
      throw e
    } finally {
      client.release()
    }
  }

  private async write(client: PoolClient, row: ActionRow, existing: ActionRow | undefined): Promise<void> {
    const vals = [
      row.actionKey, row.ownerSystem, row.state, row.attempt, row.reservationToken, row.reservedAt, row.leaseExpiresAt,
      row.executingAt ?? null, row.completedAt ?? null, row.outcomeRef ?? null, row.failureCode ?? null, row.unknownReason ?? null,
      row.reconciliation ? JSON.stringify(row.reconciliation) : null, row.updatedAt, row.version,
    ]
    if (!existing) {
      await client.query(
        `INSERT INTO artist_os_action_ledger (action_key, owner_system, state, attempt, reservation_token, reserved_at, lease_expires_at, executing_at, completed_at, outcome_ref, failure_code, unknown_reason, reconciliation, updated_at, version)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`,
        vals,
      )
      return
    }
    const res = await client.query(
      `UPDATE artist_os_action_ledger SET owner_system=$2, state=$3, attempt=$4, reservation_token=$5, reserved_at=$6, lease_expires_at=$7, executing_at=$8, completed_at=$9, outcome_ref=$10, failure_code=$11, unknown_reason=$12, reconciliation=$13, updated_at=$14, version=$15
       WHERE action_key=$1 AND version=$16`,
      [...vals, existing.version],
    )
    if (res.rowCount !== 1) throw new Error('action ledger lost update (version check failed)')
  }

  async get(actionKey: ActionKey) {
    const r = await this.pool.query('SELECT * FROM artist_os_action_ledger WHERE action_key = $1', [actionKey])
    return r.rows[0] ? fromDb(r.rows[0]) : undefined
  }

  async list(filter: { state?: LedgerState; ownerSystem?: string; limit?: number } = {}) {
    const r = await this.pool.query(
      `SELECT * FROM artist_os_action_ledger WHERE ($1::text IS NULL OR state = $1) AND ($2::text IS NULL OR owner_system = $2) ORDER BY updated_at DESC LIMIT $3`,
      [filter.state ?? null, filter.ownerSystem ?? null, Math.min(filter.limit ?? 200, 1000)],
    )
    return r.rows.map(fromDb)
  }

  async events(actionKey: ActionKey): Promise<LedgerEvent[]> {
    const r = await this.pool.query('SELECT * FROM artist_os_action_events WHERE action_key = $1 ORDER BY id', [actionKey])
    return r.rows.map((x) => ({ actionKey, at: iso(x.at)!, kind: x.kind, actor: x.actor, fromState: x.from_state, toState: x.to_state, detail: x.detail ?? undefined }))
  }

  async close() {
    await this.pool.end()
  }
}
