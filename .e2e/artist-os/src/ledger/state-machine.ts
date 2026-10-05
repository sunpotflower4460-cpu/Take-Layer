import type { ActionKey } from './action-key.js'

/**
 * Action Ledger state machine (pure). Persistence adapters call these functions inside their own
 * atomic section (a lock, or a row lock in a transaction) so every adapter shares one set of rules.
 *
 *   (no row) = AVAILABLE
 *   RESERVED ──begin──▶ EXECUTING ──complete(succeeded)──▶ SUCCEEDED
 *                              ├──complete(failed_safe)──▶ FAILED_SAFE_TO_RETRY ──reserve(owner)──▶ RESERVED
 *                              └──complete(unknown) / lease expiry──▶ OUTCOME_UNKNOWN ──reconcile──▶ RECONCILED
 *
 * OUTCOME_UNKNOWN is terminal for every sender until a reconcile with evidence: nobody sends.
 */
export const LEDGER_STATES = ['AVAILABLE', 'RESERVED', 'EXECUTING', 'SUCCEEDED', 'FAILED_SAFE_TO_RETRY', 'OUTCOME_UNKNOWN', 'RECONCILED'] as const
export type LedgerState = (typeof LEDGER_STATES)[number]
export type StoredState = Exclude<LedgerState, 'AVAILABLE'>

export interface ActionRow {
  actionKey: ActionKey
  ownerSystem: string
  state: StoredState
  /** Number of times the owner acquired this key (1 for the first). */
  attempt: number
  /** Fencing token: only the holder of the current token may begin/complete. */
  reservationToken: string
  reservedAt: string
  leaseExpiresAt: string
  executingAt?: string
  completedAt?: string
  /** Provider reference for a confirmed send (e.g. external comment id). Never reply text. */
  outcomeRef?: string
  failureCode?: string
  unknownReason?: string
  reconciliation?: { resolution: 'sent' | 'not_sent'; evidence: string; by: string; at: string }
  updatedAt: string
  /** Optimistic version, +1 on every change. */
  version: number
}

export type ReserveResult =
  | { status: 'ACQUIRED'; row: ActionRow; reservationToken: string }
  | { status: 'ALREADY_RESERVED'; heldBy: string; state: 'RESERVED' | 'EXECUTING'; leaseExpiresAt: string }
  | { status: 'ALREADY_SUCCEEDED'; heldBy: string; outcomeRef?: string }
  | { status: 'OUTCOME_UNKNOWN'; heldBy: string; reason?: string }
  | { status: 'CONFLICT'; reason: ConflictReason; detail?: string }

export type ConflictReason = 'NOT_CANONICAL_OWNER' | 'HANDOFF_ONLY' | 'UNKNOWN_OPERATION' | 'OWNER_MISMATCH' | 'SYSTEM_NEVER_EXECUTES'

export type TransitionError = 'NOT_FOUND' | 'WRONG_STATE' | 'STALE_TOKEN' | 'LEASE_EXPIRED' | 'EVIDENCE_REQUIRED'
export type TransitionResult = { ok: true; row: ActionRow } | { ok: false; error: TransitionError; state?: LedgerState }

export interface Timing {
  now: Date
  /** Lease for RESERVED (time allowed to call `begin`). */
  reserveLeaseMs: number
  /** Lease for EXECUTING (time allowed to finish the provider call). */
  executeLeaseMs: number
}

const iso = (d: Date) => d.toISOString()
const expired = (row: ActionRow, now: Date) => Date.parse(row.leaseExpiresAt) <= now.getTime()

/**
 * Applies time-based consequences before anything else. An EXECUTING row whose lease ran out is
 * OUTCOME_UNKNOWN (the provider call may have landed); a RESERVED row whose lease ran out is just stale.
 */
export function settle(row: ActionRow | undefined, now: Date): ActionRow | undefined {
  if (!row) return row
  if (row.state === 'EXECUTING' && expired(row, now)) {
    return { ...row, state: 'OUTCOME_UNKNOWN', unknownReason: 'LEASE_EXPIRED_WHILE_EXECUTING', updatedAt: iso(now), version: row.version + 1 }
  }
  return row
}

export function applyReserve(existing: ActionRow | undefined, req: { actionKey: ActionKey; owner: string; token: string }, t: Timing): { row?: ActionRow; result: ReserveResult } {
  const row = settle(existing, t.now)
  const fresh = (attempt: number, version: number): ActionRow => ({
    actionKey: req.actionKey,
    ownerSystem: req.owner,
    state: 'RESERVED',
    attempt,
    reservationToken: req.token,
    reservedAt: iso(t.now),
    leaseExpiresAt: iso(new Date(t.now.getTime() + t.reserveLeaseMs)),
    updatedAt: iso(t.now),
    version,
  })

  if (!row) {
    const r = fresh(1, 1)
    return { row: r, result: { status: 'ACQUIRED', row: r, reservationToken: req.token } }
  }

  switch (row.state) {
    case 'SUCCEEDED':
      return { row: row !== existing ? row : undefined, result: { status: 'ALREADY_SUCCEEDED', heldBy: row.ownerSystem, outcomeRef: row.outcomeRef } }
    case 'RECONCILED':
      if (row.reconciliation?.resolution === 'sent') return { result: { status: 'ALREADY_SUCCEEDED', heldBy: row.ownerSystem, outcomeRef: row.outcomeRef } }
      return retryable(row, req, t, fresh)
    case 'OUTCOME_UNKNOWN':
      // Fail closed for EVERYONE, including the owner. Persist the lease-expiry transition if it just happened.
      return { row: row !== existing ? row : undefined, result: { status: 'OUTCOME_UNKNOWN', heldBy: row.ownerSystem, reason: row.unknownReason } }
    case 'FAILED_SAFE_TO_RETRY':
      return retryable(row, req, t, fresh)
    case 'RESERVED':
    case 'EXECUTING':
      if (row.state === 'RESERVED' && expired(row, t.now) && row.ownerSystem === req.owner) {
        // Stale reservation of the same owner (crashed before begin): safe to take over, nothing was sent.
        const r = fresh(row.attempt + 1, row.version + 1)
        return { row: r, result: { status: 'ACQUIRED', row: r, reservationToken: req.token } }
      }
      return { result: { status: 'ALREADY_RESERVED', heldBy: row.ownerSystem, state: row.state, leaseExpiresAt: row.leaseExpiresAt } }
  }
}

function retryable(row: ActionRow, req: { owner: string; token: string; actionKey: ActionKey }, t: Timing, fresh: (attempt: number, version: number) => ActionRow): { row?: ActionRow; result: ReserveResult } {
  // A retry stays with the same owner. Handing the action to someone else needs an operator, not a race.
  if (row.ownerSystem !== req.owner) return { result: { status: 'CONFLICT', reason: 'OWNER_MISMATCH', detail: `held by ${row.ownerSystem}` } }
  const r = fresh(row.attempt + 1, row.version + 1)
  return { row: r, result: { status: 'ACQUIRED', row: r, reservationToken: req.token } }
}

export function applyBegin(existing: ActionRow | undefined, req: { token: string }, t: Timing): { row?: ActionRow; result: TransitionResult } {
  const row = settle(existing, t.now)
  if (!row) return { result: { ok: false, error: 'NOT_FOUND' } }
  if (row.state !== 'RESERVED') return { row: row !== existing ? row : undefined, result: { ok: false, error: 'WRONG_STATE', state: row.state } }
  if (row.reservationToken !== req.token) return { result: { ok: false, error: 'STALE_TOKEN' } }
  if (expired(row, t.now)) return { result: { ok: false, error: 'LEASE_EXPIRED' } }
  const next: ActionRow = { ...row, state: 'EXECUTING', executingAt: iso(t.now), leaseExpiresAt: iso(new Date(t.now.getTime() + t.executeLeaseMs)), updatedAt: iso(t.now), version: row.version + 1 }
  return { row: next, result: { ok: true, row: next } }
}

export type CompleteOutcome =
  | { outcome: 'succeeded'; outcomeRef?: string }
  | { outcome: 'failed_safe'; failureCode: string }
  | { outcome: 'unknown'; reason: string }

export function applyComplete(existing: ActionRow | undefined, req: { token: string } & CompleteOutcome, t: Timing): { row?: ActionRow; result: TransitionResult } {
  const row = settle(existing, t.now)
  if (!row) return { result: { ok: false, error: 'NOT_FOUND' } }
  if (row.reservationToken !== req.token) return { row: row !== existing ? row : undefined, result: { ok: false, error: 'STALE_TOKEN' } }
  // The executor that holds the token may settle its own call even if its lease lapsed in the meantime
  // (EXECUTING → OUTCOME_UNKNOWN by expiry), but only for a lease-expiry unknown — never an explicit one.
  const lateSettle = row.state === 'OUTCOME_UNKNOWN' && row.unknownReason === 'LEASE_EXPIRED_WHILE_EXECUTING'
  if (row.state !== 'EXECUTING' && !lateSettle) return { row: row !== existing ? row : undefined, result: { ok: false, error: 'WRONG_STATE', state: row.state } }
  const base = { ...row, completedAt: iso(t.now), updatedAt: iso(t.now), version: row.version + 1 }
  const next: ActionRow =
    req.outcome === 'succeeded'
      ? { ...base, state: 'SUCCEEDED', outcomeRef: req.outcomeRef, unknownReason: undefined }
      : req.outcome === 'failed_safe'
        ? { ...base, state: 'FAILED_SAFE_TO_RETRY', failureCode: req.failureCode, unknownReason: undefined }
        : { ...base, state: 'OUTCOME_UNKNOWN', unknownReason: req.reason }
  return { row: next, result: { ok: true, row: next } }
}

export function applyReconcile(existing: ActionRow | undefined, req: { resolution: 'sent' | 'not_sent'; evidence: string; by: string; outcomeRef?: string }, t: Timing): { row?: ActionRow; result: TransitionResult } {
  const row = settle(existing, t.now)
  if (!row) return { result: { ok: false, error: 'NOT_FOUND' } }
  if (row.state !== 'OUTCOME_UNKNOWN') return { row: row !== existing ? row : undefined, result: { ok: false, error: 'WRONG_STATE', state: row.state } }
  if (!req.evidence.trim()) return { result: { ok: false, error: 'EVIDENCE_REQUIRED' } }
  const next: ActionRow = {
    ...row,
    state: 'RECONCILED',
    outcomeRef: req.outcomeRef ?? row.outcomeRef,
    reconciliation: { resolution: req.resolution, evidence: req.evidence.slice(0, 500), by: req.by, at: iso(t.now) },
    updatedAt: iso(t.now),
    version: row.version + 1,
  }
  return { row: next, result: { ok: true, row: next } }
}
