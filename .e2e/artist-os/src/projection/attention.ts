import type { ClientResult, SpecialistClient } from '../clients/base.js'
import type { ActionTarget, AttentionItem } from '../contracts/service.js'
import { type SourceRef, type SystemId, sourceRefKey } from '../core/common.js'
import type { TraceContext, TraceLog } from '../core/trace.js'
import type { PolicyGateway } from '../policy/gateway.js'

const PRIORITY_RANK = { urgent: 3, high: 2, normal: 1, low: 0 } as const

export interface AttentionEntry extends AttentionItem {
  /** `machine` = Artist OS can forward the decision to the source endpoint; `human_only` = open the source UI. */
  actionMode: 'machine' | 'link_out' | 'human_only'
}

/**
 * Attention Queue = PROJECTION of source-system items. Nothing here is stored
 * as approval state: the specialist is always the one who approves.
 */
export function buildAttentionQueue(items: readonly AttentionItem[]): AttentionEntry[] {
  const seen = new Map<string, AttentionEntry>()
  for (const it of items) {
    const key = sourceRefKey({ system: it.sourceSystem, entityType: it.sourceEntityType, entityId: it.sourceEntityId }) + `|${it.kind}`
    const mode: AttentionEntry['actionMode'] = !it.action ? 'human_only' : it.action.type === 'endpoint' ? 'machine' : 'link_out'
    const entry = { ...it, actionMode: mode }
    const prev = seen.get(key)
    if (!prev || PRIORITY_RANK[entry.priority] > PRIORITY_RANK[prev.priority]) seen.set(key, entry)
  }
  return [...seen.values()].sort(
    (a, b) => PRIORITY_RANK[b.priority] - PRIORITY_RANK[a.priority] || (a.dueAt ?? a.createdAt).localeCompare(b.dueAt ?? b.createdAt),
  )
}

export type DecisionOutcome =
  | { kind: 'forwarded'; httpStatus: number }
  | { kind: 'link_out'; url: string }
  | { kind: 'refused'; reason: 'no_machine_action' | 'policy' | 'no_client' | 'specialist_rejected' | 'uncertain_outcome'; detail: string }

export interface DecisionDeps {
  clients: Map<SystemId, SpecialistClient>
  policy: PolicyGateway
  trace?: TraceLog
  traceCtx?: TraceContext
  /** Identity of the human who clicked. Required: an approval with no human is not an approval. */
  humanActorId: string
  workspaceRef: string
}

/**
 * Human clicked approve/reject in Artist OS ⇒ call the SOURCE system's approval endpoint.
 * Artist OS never flips a local "approved" flag and stops. The specialist's reply is the truth;
 * on a timeout the outcome is UNCERTAIN and must be reconciled, never retried blindly.
 */
export async function decideAttention(
  item: AttentionEntry,
  decision: 'approve' | 'reject',
  deps: DecisionDeps,
): Promise<DecisionOutcome> {
  if (!deps.humanActorId.trim()) return { kind: 'refused', reason: 'policy', detail: 'a human actor is required' }
  const action: ActionTarget | undefined = item.action
  if (!action) return { kind: 'refused', reason: 'no_machine_action', detail: 'source offers no action; handle it in the source system' }
  if (action.type === 'deeplink') return { kind: 'link_out', url: action.url }

  // Approving a specialist write is WRITE_EXTERNAL; the human click satisfies an `approval` verdict but not `deny`/`handoff`.
  const eff = deps.policy.evaluate({ operation: `${item.sourceSystem}.${item.sourceEntityType}.${decision}`, risk: 'WRITE_EXTERNAL', system: item.sourceSystem })
  if (eff.verdict === 'deny' || eff.verdict === 'handoff') {
    return { kind: 'refused', reason: 'policy', detail: `${eff.verdict}: ${eff.binding.map((b) => b.reason).join('; ')}` }
  }
  const client = deps.clients.get(item.sourceSystem)
  if (!client) return { kind: 'refused', reason: 'no_client', detail: item.sourceSystem }

  if (deps.trace && deps.traceCtx) {
    await deps.trace.record(deps.traceCtx, {
      eventType: `attention.${decision}.requested`,
      producer: 'artist-os',
      workspaceRef: deps.workspaceRef,
      subjectRefs: [{ system: item.sourceSystem, entityType: item.sourceEntityType, entityId: item.sourceEntityId } satisfies SourceRef],
      summary: `human ${deps.humanActorId} ${decision}d via Artist OS`,
    })
  }
  const res: ClientResult<{ status: number }> = await client.forwardAction(action, { decision, actor: deps.humanActorId })
  if (res.ok) return { kind: 'forwarded', httpStatus: res.value.status }
  if (res.reason === 'timeout' || res.reason === 'network') return { kind: 'refused', reason: 'uncertain_outcome', detail: res.detail }
  return { kind: 'refused', reason: 'specialist_rejected', detail: res.detail }
}
