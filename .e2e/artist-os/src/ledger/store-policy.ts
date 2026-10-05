import type { StoreInfo } from './storage.js'

export type DeployEnvironment = 'development' | 'test' | 'production'

/**
 * Parses ARTIST_OS_ENV. Anything unset or unrecognised is PRODUCTION: the strict reading wins.
 * Local development must opt in explicitly with ARTIST_OS_ENV=development.
 */
export function resolveEnvironment(raw: string | undefined): DeployEnvironment {
  const v = raw?.trim().toLowerCase()
  return v === 'development' || v === 'test' ? v : 'production'
}

export type WriteCoordination =
  | { state: 'enabled'; reason: string }
  | { state: 'disabled'; reason: string }
  | { state: 'refused'; reason: 'STORE_NOT_DURABLE'; detail: string }

/**
 * Store Policy (docs/architecture/STORE_POLICY.md):
 *
 *   development / test                 any store allowed
 *   production, read-only              any store; coordination stays disabled (degraded)
 *   production + write coordination    durable, atomic, multi-process-safe store REQUIRED, else refused
 *
 * `requested` is the explicit operator switch ARTIST_OS_WRITE_COORDINATION=enabled. The decision is
 * recomputed at startup and exposed through health, so a refusal is visible, not silent.
 */
export function evaluateWriteCoordination(input: { environment: DeployEnvironment; requested: boolean; store: StoreInfo; /** Name of the switch, for messages. */ switchName?: string; subject?: string }): WriteCoordination {
  const { environment, requested, store } = input
  const switchName = input.switchName ?? 'ARTIST_OS_WRITE_COORDINATION'
  const subject = input.subject ?? 'specialists must fail closed on inbound replies'
  const safe = store.durable && store.atomicReservation && store.multiProcessSafe
  if (environment !== 'production') {
    return { state: 'enabled', reason: `${environment}: ${store.kind} store allowed for local use` }
  }
  if (!requested) return { state: 'disabled', reason: `production: ${switchName} is not enabled; ${subject}` }
  if (!safe) {
    return {
      state: 'refused',
      reason: 'STORE_NOT_DURABLE',
      detail: `production ${input.switchName ? 'use' : 'write coordination'} needs a durable, atomic, multi-process-safe store; ${store.kind} is not (durable=${store.durable}, atomic=${store.atomicReservation}, multiProcessSafe=${store.multiProcessSafe})`,
    }
  }
  return { state: 'enabled', reason: `production: ${store.kind} store is durable and atomic` }
}
