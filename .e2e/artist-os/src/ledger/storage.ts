import type { ActionKey } from './action-key.js'
import type { ActionRow, LedgerState } from './state-machine.js'

export type StoreKind = 'memory' | 'json-file' | 'postgres'

/**
 * What a store can honestly promise. The Store Policy decides, from this and the
 * environment, whether cross-system external-write coordination may run on it.
 */
export interface StoreInfo {
  kind: StoreKind
  /** Survives a process restart. */
  durable: boolean
  /** Reservation is a single atomic section (DB transaction / unique constraint), not check-then-write. */
  atomicReservation: boolean
  /** Safe with several Artist OS processes/instances writing at once. */
  multiProcessSafe: boolean
}

export interface LedgerEvent {
  actionKey: ActionKey
  at: string
  kind: 'reserve' | 'begin' | 'complete' | 'reconcile' | 'lease_expired' | 'reject'
  actor: string
  fromState: LedgerState
  toState: LedgerState
  detail?: string
}

export interface RowDecision<T> {
  /** Row to persist (omit to leave unchanged). */
  row?: ActionRow
  result: T
  event?: Omit<LedgerEvent, 'actionKey' | 'at'>
}

/**
 * Persistence port for the Action Ledger. The ONE write primitive is `withRow`: the adapter
 * must run `decide` with the current row while holding exclusive access to that action key
 * (a row lock inside a transaction, a unique-constraint insert, or a process-wide section for
 * dev stores) and persist the returned row before releasing it. Check-then-insert outside such a
 * section is forbidden: it is exactly the race this ledger exists to remove.
 */
export interface LedgerStorage {
  readonly info: StoreInfo
  withRow<T>(actionKey: ActionKey, decide: (existing: ActionRow | undefined) => RowDecision<T>, now: Date): Promise<T>
  get(actionKey: ActionKey): Promise<ActionRow | undefined>
  list(filter?: { state?: LedgerState; ownerSystem?: string; limit?: number }): Promise<ActionRow[]>
  events(actionKey: ActionKey): Promise<LedgerEvent[]>
  close?(): Promise<void>
}
