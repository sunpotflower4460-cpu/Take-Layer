import type { InboundEvent } from '../contracts/inbound.js'
import type { RelationshipEnrichmentPayload } from '../contracts/relationship.js'
import type { SystemId } from '../core/common.js'
import { type ActionKey, makeActionKey, normalizeExternalEventId, type ActionOperation } from '../ledger/action-key.js'
import { type ManagedOwner, ownershipFor } from '../ledger/ownership.js'
import type { ActionRow } from '../ledger/state-machine.js'

export type ReplyStatus = 'awaiting_approval' | 'approved_scheduled' | 'reserved' | 'executing' | 'sent' | 'retry_ready' | 'outcome_unknown' | 'handoff' | 'no_reply_needed' | 'unmapped'

export interface Contribution {
  system: SystemId
  role: 'canonical_inbound' | 'relationship_context' | 'draft_source' | 'strategy'
  summary?: string
}

/**
 * One inbound event as the human sees it: who OWNS the reply (always exactly one executor),
 * who contributed context, and where it stands. Contributions can never add an executor.
 */
export interface ReplyOwnershipView {
  actionKey?: ActionKey
  platform: string
  summary: string
  receivedAt: string
  /** The single execution owner per the ownership table (or `handoff`). */
  executionOwner: ManagedOwner | 'unmapped'
  approvalOwner?: SystemId
  contributions: Contribution[]
  /** Intelligence about the contact, from SNS-providers. Never changes the owner and never authorizes anything. */
  relationship?: { provider: 'sns-providers'; stage: string; value: number | null; label: string; priority: string; recommendedHandling: string; reasonCodes: readonly string[] }
  status: ReplyStatus
  /** Plain-language line for Today/Attention. */
  line: string
  /** Contributions that tried to act as an executor and were discarded. */
  rejectedContributions: Contribution[]
}

const operationFor = (e: InboundEvent): ActionOperation | undefined =>
  e.kind === 'comment' ? 'comment_reply' : e.kind === 'dm' ? 'dm_reply' : e.kind === 'mention' ? 'mention_reply' : undefined

export function buildReplyOwnershipView(
  e: InboundEvent,
  ledgerRow: ActionRow | undefined,
  extra: { contributions?: readonly (Contribution & { role: string })[]; relationship?: RelationshipEnrichmentPayload } = {},
): ReplyOwnershipView {
  const op = operationFor(e)
  const rule = op ? ownershipFor(e.platform, op) : undefined
  const base = { platform: e.platform, summary: e.textExcerpt ? `${e.platform} ${e.kind}: ${e.textExcerpt}` : `${e.platform} ${e.kind} (${e.authorHandle ?? 'unknown'})`, receivedAt: e.receivedAt }
  const allowed = new Set<Contribution['role']>(['canonical_inbound', 'relationship_context', 'draft_source', 'strategy'])
  const contributions: Contribution[] = [{ system: 'my-sns', role: 'canonical_inbound' }]
  const rejected: Contribution[] = []
  for (const c of extra.contributions ?? []) (allowed.has(c.role as Contribution['role']) ? contributions : rejected).push(c as Contribution)

  if (!op || !rule) return { ...base, executionOwner: 'unmapped', contributions, rejectedContributions: rejected, status: 'unmapped', line: `${e.platform} ${e.kind}: no ownership rule — a human handles it` }
  const key = makeActionKey({ platform: e.platform, operation: op, externalEventId: normalizeExternalEventId(e.externalEventId) })
  const owner = rule.managedOwner
  // Enrichment must be about THIS event: the join is (platform, native event id), never anything fuzzier.
  const rel = extra.relationship && extra.relationship.subject.platform === e.platform && extra.relationship.subject.externalEventId === normalizeExternalEventId(e.externalEventId) ? extra.relationship : undefined
  const relationship = rel ? { provider: 'sns-providers' as const, stage: rel.relationshipStage, value: rel.relationshipValue, label: relationshipLabel(rel), priority: rel.priority, recommendedHandling: rel.recommendedHandling, reasonCodes: rel.reasonCodes } : undefined
  if (rel) contributions.push({ system: 'sns-providers', role: 'relationship_context', summary: relationship!.label })
  const ctx = contributions.filter((c) => c.role !== 'canonical_inbound').map((c) => `${c.role === 'relationship_context' ? 'Relationship context' : c.role === 'draft_source' ? 'Draft source' : 'Strategy'}: ${c.system}`)

  let status: ReplyStatus
  if (ledgerRow?.state === 'OUTCOME_UNKNOWN') status = 'outcome_unknown'
  else if (ledgerRow?.state === 'SUCCEEDED' || (ledgerRow?.state === 'RECONCILED' && ledgerRow.reconciliation?.resolution === 'sent') || e.replyState === 'sent') status = 'sent'
  else if (ledgerRow?.state === 'EXECUTING') status = 'executing'
  else if (ledgerRow?.state === 'RESERVED') status = 'reserved'
  else if (ledgerRow?.state === 'FAILED_SAFE_TO_RETRY' || ledgerRow?.state === 'RECONCILED') status = 'retry_ready'
  else if (owner === 'handoff') status = 'handoff'
  else if (e.replyState === 'scheduled') status = 'approved_scheduled'
  else if (!e.needsAction) status = 'no_reply_needed'
  else status = 'awaiting_approval'

  const statusText: Record<ReplyStatus, string> = {
    awaiting_approval: 'Awaiting approval', approved_scheduled: 'Approved, scheduled', reserved: 'Reserved for sending', executing: 'Sending',
    sent: 'Sent', retry_ready: 'Send failed safely; retry allowed for the owner only', outcome_unknown: 'OUTCOME UNKNOWN — nobody will resend until you reconcile',
    handoff: 'Reply by hand (no supported API)', no_reply_needed: 'No reply needed', unmapped: 'No rule',
  }
  const line = [`${e.platform} ${e.kind}`, `Owner: ${owner === 'handoff' ? 'you (manual)' : owner}`, ...(relationship ? [`Relationship: ${relationship.label} (via sns-providers)`] : []), ...ctx.filter((c) => !(relationship && c.startsWith('Relationship context'))), `Status: ${statusText[status]}`].join(' · ')
  return { ...base, actionKey: key, executionOwner: owner, approvalOwner: rule.approvalOwner, contributions, ...(relationship ? { relationship } : {}), rejectedContributions: rejected, status, line }
}

/** Human label from machine fields only (no free text from the provider): "High value / repeat engager". */
export function relationshipLabel(r: Pick<RelationshipEnrichmentPayload, 'relationshipValue' | 'reasonCodes' | 'relationshipStage'>): string {
  const value = r.relationshipValue === null ? 'Value unknown' : r.relationshipValue >= 0.7 ? 'High value' : r.relationshipValue >= 0.35 ? 'Medium value' : 'Low value'
  const tags: string[] = []
  if (r.reasonCodes.includes('repeat-interaction')) tags.push('repeat engager')
  if (r.reasonCodes.includes('new-contact')) tags.push('new contact')
  if (r.reasonCodes.includes('dormant')) tags.push('dormant')
  if (r.reasonCodes.includes('no-candidate-match')) tags.push('not a known candidate')
  return [value, ...tags].join(' / ')
}
