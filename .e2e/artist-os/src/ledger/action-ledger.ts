import { type Clock, randomIdGenerator, systemClock } from '../core/common.js'
import { type ActionKey, type ActionKeyParts, makeActionKey } from './action-key.js'
import { NEVER_EXECUTES_INBOUND_REPLIES, ownershipFor } from './ownership.js'
import {
  type ActionRow,
  type CompleteOutcome,
  type ReserveResult,
  type Timing,
  type TransitionResult,
  applyBegin,
  applyComplete,
  applyReconcile,
  applyReserve,
  settle,
} from './state-machine.js'
import type { LedgerStorage } from './storage.js'

export interface ActionLedgerOptions {
  clock?: Clock
  newToken?: () => string
  reserveLeaseMs?: number
  executeLeaseMs?: number
}

/**
 * The cross-system external-write ledger. The caller's identity (`owner`) is supplied by the
 * transport layer from an authenticated credential, never from request content.
 *
 * Protocol for an inbound reply:
 *   1. source system has an approved reply
 *   2. reserve(key)  → ACQUIRED, else STOP (do not send)
 *   3. begin(key)    → EXECUTING; only then call the provider
 *   4. complete(key) → succeeded | failed_safe | unknown
 *   5. reconcile(key) with evidence if a send ended OUTCOME_UNKNOWN
 */
export class ActionLedger {
  private readonly clock: Clock
  private readonly newToken: () => string
  private readonly reserveLeaseMs: number
  private readonly executeLeaseMs: number

  constructor(readonly storage: LedgerStorage, opts: ActionLedgerOptions = {}) {
    this.clock = opts.clock ?? systemClock
    this.newToken = opts.newToken ?? (() => randomIdGenerator('rsv'))
    this.reserveLeaseMs = opts.reserveLeaseMs ?? 2 * 60_000
    this.executeLeaseMs = opts.executeLeaseMs ?? 10 * 60_000
  }

  private timing(): Timing {
    return { now: this.clock(), reserveLeaseMs: this.reserveLeaseMs, executeLeaseMs: this.executeLeaseMs }
  }

  /** Ownership is checked BEFORE touching storage: a non-owner never creates a row, so it can never squat a key. */
  async reserve(owner: string, parts: ActionKeyParts): Promise<ReserveResult> {
    const actionKey = makeActionKey(parts)
    if ((NEVER_EXECUTES_INBOUND_REPLIES as readonly string[]).includes(owner)) {
      return { status: 'CONFLICT', reason: 'SYSTEM_NEVER_EXECUTES', detail: `${owner} may not execute inbound replies` }
    }
    const rule = ownershipFor(parts.platform, parts.operation)
    if (!rule) return { status: 'CONFLICT', reason: 'UNKNOWN_OPERATION', detail: `${parts.platform}/${parts.operation}` }
    if (rule.managedOwner === 'handoff') return { status: 'CONFLICT', reason: 'HANDOFF_ONLY', detail: 'a human performs this reply' }
    if (rule.managedOwner !== owner) {
      return { status: 'CONFLICT', reason: 'NOT_CANONICAL_OWNER', detail: `canonical owner is ${rule.managedOwner}` }
    }
    const t = this.timing()
    const token = this.newToken()
    return this.storage.withRow(
      actionKey,
      (existing) => {
        const before = existing?.state ?? 'AVAILABLE'
        const settled = settle(existing, t.now)
        const r = applyReserve(existing, { actionKey, owner, token }, t)
        const to = r.result.status === 'ACQUIRED' ? 'RESERVED' : (r.row ?? settled)?.state ?? before
        return { row: r.row, result: r.result, event: { kind: r.result.status === 'ACQUIRED' ? 'reserve' : 'reject', actor: owner, fromState: before, toState: to, detail: r.result.status } }
      },
      t.now,
    )
  }

  begin(owner: string, actionKey: ActionKey, reservationToken: string): Promise<TransitionResult> {
    return this.transition(owner, actionKey, 'begin', (row, t) => applyBegin(row, { token: reservationToken }, t))
  }

  complete(owner: string, actionKey: ActionKey, reservationToken: string, outcome: CompleteOutcome): Promise<TransitionResult> {
    return this.transition(owner, actionKey, 'complete', (row, t) => applyComplete(row, { token: reservationToken, ...outcome }, t))
  }

  /** `by` is the authenticated reconciler (the owning system or an operator). */
  reconcile(by: string, actionKey: ActionKey, input: { resolution: 'sent' | 'not_sent'; evidence: string; outcomeRef?: string }): Promise<TransitionResult> {
    return this.transition(by, actionKey, 'reconcile', (row, t) => applyReconcile(row, { ...input, by }, t))
  }

  private transition(
    actor: string,
    actionKey: ActionKey,
    kind: 'begin' | 'complete' | 'reconcile',
    fn: (row: ActionRow | undefined, t: Timing) => { row?: ActionRow; result: TransitionResult },
  ): Promise<TransitionResult> {
    const t = this.timing()
    return this.storage.withRow(
      actionKey,
      (existing) => {
        const r = fn(existing, t)
        // Only the owner (or an operator doing a reconcile) may drive an existing action.
        if (existing && kind !== 'reconcile' && existing.ownerSystem !== actor) {
          return { result: { ok: false, error: 'STALE_TOKEN' } as TransitionResult, event: { kind: 'reject', actor, fromState: existing.state, toState: existing.state, detail: 'not the owner' } }
        }
        const before = existing?.state ?? 'AVAILABLE'
        return { row: r.row, result: r.result, event: { kind: r.result.ok ? kind : 'reject', actor, fromState: before, toState: r.result.ok ? r.result.row.state : before, detail: r.result.ok ? undefined : r.result.error } }
      },
      t.now,
    )
  }

  async get(actionKey: ActionKey): Promise<ActionRow | { state: 'AVAILABLE' }> {
    const row = await this.storage.get(actionKey)
    // Report lease-expiry honestly on reads too (the write happens on the next mutation).
    return settle(row, this.clock()) ?? { state: 'AVAILABLE' }
  }

  list(filter?: Parameters<LedgerStorage['list']>[0]) {
    return this.storage.list(filter).then((rows) => rows.map((r) => settle(r, this.clock()) ?? r))
  }
}
