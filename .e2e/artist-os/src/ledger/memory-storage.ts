import type { ActionKey } from './action-key.js'
import type { ActionRow, LedgerState } from './state-machine.js'
import type { LedgerEvent, LedgerStorage, RowDecision, StoreInfo } from './storage.js'

/**
 * In-process storage for tests and local development. `withRow` runs `decide` synchronously
 * (no await between read and write), so within one process it is atomic. It is NOT
 * safe across processes and NOT durable: the Store Policy refuses it for production coordination.
 */
export class MemoryLedgerStorage implements LedgerStorage {
  readonly info: StoreInfo = { kind: 'memory', durable: false, atomicReservation: true, multiProcessSafe: false }
  protected readonly rows = new Map<ActionKey, ActionRow>()
  protected readonly log: LedgerEvent[] = []

  /** Hook for subclasses that persist after each write (still synchronous, still inside the section). */
  protected afterWrite(): void {}

  async withRow<T>(actionKey: ActionKey, decide: (existing: ActionRow | undefined) => RowDecision<T>, now: Date): Promise<T> {
    const before = this.rows.get(actionKey)
    const d = decide(before)
    if (d.row) this.rows.set(actionKey, d.row)
    if (d.event) this.log.push({ ...d.event, actionKey, at: now.toISOString() })
    if (d.row || d.event) this.afterWrite()
    return d.result
  }

  async get(actionKey: ActionKey) {
    return this.rows.get(actionKey)
  }

  async list(filter: { state?: LedgerState; ownerSystem?: string; limit?: number } = {}) {
    return [...this.rows.values()]
      .filter((r) => (!filter.state || r.state === filter.state) && (!filter.ownerSystem || r.ownerSystem === filter.ownerSystem))
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
      .slice(0, filter.limit ?? 200)
  }

  async events(actionKey: ActionKey) {
    return this.log.filter((e) => e.actionKey === actionKey)
  }

  snapshot(): ActionRow[] {
    return [...this.rows.values()]
  }
  restore(rows: readonly ActionRow[]): void {
    this.rows.clear()
    for (const r of rows) this.rows.set(r.actionKey, r)
  }
}
