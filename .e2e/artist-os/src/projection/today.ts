import type { SpecialistClient } from '../clients/base.js'
import type { ActivityItem, AttentionItem } from '../contracts/service.js'
import type { Clock, SystemId } from '../core/common.js'
import { NEEDS_HUMAN_STATES, type EquipmentRegistry } from '../equipment/registry.js'
import type { JobQueue } from '../runner/queue-port.js'
import { type AttentionEntry, buildAttentionQueue } from './attention.js'
import type { ActionLedger } from '../ledger/action-ledger.js'
import { MySnsClient, SnsProvidersClient } from '../clients/specialists.js'
import { acceptEnrichmentArtifacts } from '../contracts/relationship.js'
import { type ReplyOwnershipView, buildReplyOwnershipView } from './reply-ownership.js'

export interface TodayEntry {
  sourceSystem: SystemId
  sourceEntityId: string
  sourceEntityType: string
  summary: string
  status: string
  priority?: string
  progress?: number
  at: string
  actionCapability: 'machine' | 'link_out' | 'human_only' | 'none'
}

export interface TodayProjection {
  generatedAt: string
  autoCompleted: TodayEntry[]
  running: TodayEntry[]
  needsYou: TodayEntry[]
  scheduled: TodayEntry[]
  attention: AttentionEntry[]
  /** Inbound replies with exactly one execution owner each, plus who contributed what. */
  replyOwnership: ReplyOwnershipView[]
  /** Sources we could not read. Shown explicitly — silence must never look like "all clear". */
  unreadableSources: { system: SystemId; reason: string }[]
}

export interface TodayDeps {
  clients: Map<SystemId, SpecialistClient>
  queue?: JobQueue
  equipment?: EquipmentRegistry
  clock: Clock
  ledger?: ActionLedger
}

const fromActivity = (a: ActivityItem): TodayEntry => ({
  sourceSystem: a.sourceSystem,
  sourceEntityId: a.sourceEntityId,
  sourceEntityType: a.sourceEntityType,
  summary: a.summary,
  status: a.state,
  progress: a.progress,
  at: a.at,
  actionCapability: 'none',
})

const fromAttention = (a: AttentionEntry): TodayEntry => ({
  sourceSystem: a.sourceSystem,
  sourceEntityId: a.sourceEntityId,
  sourceEntityType: a.sourceEntityType,
  summary: a.summary,
  status: a.kind,
  priority: a.priority,
  at: a.createdAt,
  actionCapability: a.actionMode,
})

/**
 * Today = projection, not a task database. Nothing here is persisted; every entry
 * names its source system and entity so the human acts there (or via forwarded approval).
 */
export async function buildToday(deps: TodayDeps): Promise<TodayProjection> {
  const now = deps.clock().toISOString()
  const activity: ActivityItem[] = []
  const attentionRaw: AttentionItem[] = []
  const unreadable: TodayProjection['unreadableSources'] = []

  await Promise.all(
    [...deps.clients.entries()].map(async ([system, client]) => {
      const r = await client.status()
      if (!r.ok) {
        if (r.reason !== 'not_configured') unreadable.push({ system, reason: `${r.reason}: ${r.detail}` })
        else unreadable.push({ system, reason: 'not configured' })
        return
      }
      activity.push(...r.value.activity)
      attentionRaw.push(...r.value.attention)
    }),
  )

  // Artist OS's own sources: Mac jobs and equipment (it IS the source of truth for these).
  const jobs = (await deps.queue?.list()) ?? []
  const autoCompleted = activity.filter((a) => a.state === 'completed').map(fromActivity)
  const running = activity.filter((a) => a.state === 'running').map(fromActivity)
  const scheduled = activity.filter((a) => a.state === 'scheduled').map(fromActivity)

  for (const j of jobs) {
    const entry: TodayEntry = {
      sourceSystem: 'mac-runner',
      sourceEntityId: j.jobId,
      sourceEntityType: 'mac_job',
      summary: `${j.jobType}${j.currentStage ? ` — ${j.currentStage}` : ''}`,
      status: j.status,
      progress: j.progress,
      at: j.completedAt ?? j.claimedAt ?? j.createdAt,
      actionCapability: 'none',
    }
    if (j.status === 'COMPLETED') autoCompleted.push(entry)
    else if (['CLAIMED', 'PREPARING', 'RUNNING', 'VERIFYING'].includes(j.status)) running.push(entry)
    else if (j.status === 'QUEUED') scheduled.push(entry)
    else if (j.status === 'FAILED' || j.status === 'BLOCKED') {
      attentionRaw.push({
        sourceSystem: 'artist-os',
        sourceEntityId: j.jobId,
        sourceEntityType: 'mac_job',
        kind: 'failure',
        summary: `${j.jobType} ${j.status.toLowerCase()}${j.error ? `: ${j.error.message}` : ''}`,
        priority: 'normal',
        createdAt: j.completedAt ?? j.createdAt,
      })
    }
  }

  for (const e of deps.equipment?.list() ?? []) {
    if (NEEDS_HUMAN_STATES.has(e.state)) {
      attentionRaw.push({
        sourceSystem: 'artist-os',
        sourceEntityId: e.equipmentId,
        sourceEntityType: 'equipment',
        kind: e.state === 'AUTH_REQUIRED' ? 'auth' : 'policy',
        summary: `${e.displayName}: ${e.state}. A human decision is needed; Artist OS never purchases.`,
        priority: 'low',
        createdAt: e.stateUpdatedAt ?? now,
      })
    }
  }

  // Inbound reply ownership: canonical events from My-SNS joined with the Action Ledger. A 404 means the
  // contract is not deployed there yet, which is not an outage.
  const replyOwnership: ReplyOwnershipView[] = []
  const sns = deps.clients.get('my-sns')
  if (sns instanceof MySnsClient) {
    const inbound = await sns.inboundEvents()
    if (inbound.ok) {
      // Relationship intelligence (SNS-providers), joined by (platform, native event id). Optional and read-only.
      const enrichmentByKey = new Map<string, import('../contracts/relationship.js').RelationshipEnrichmentPayload>()
      const prov = deps.clients.get('sns-providers')
      if (prov instanceof SnsProvidersClient) {
        const enr = await prov.relationshipEnrichment()
        if (enr.ok) {
          const { accepted, rejected } = acceptEnrichmentArtifacts(enr.value.artifacts)
          for (const a of accepted) enrichmentByKey.set(`${a.payload.subject.platform}:${a.payload.subject.externalEventId}`, a.payload)
          if (rejected > 0) unreadable.push({ system: 'sns-providers', reason: `${rejected} malformed enrichment artifact(s) ignored` })
          // A capped report is partial, not wrong: events beyond the cap simply show no relationship context (never a guess).
          if (enr.value.truncated || enr.value.hasMore) unreadable.push({ system: 'sns-providers', reason: 'relationship-enrichment is truncated: some inbound events have no relationship context' })
        } else if (enr.httpStatus !== 404 && enr.reason !== 'not_configured') {
          unreadable.push({ system: 'sns-providers', reason: `relationship-enrichment: ${enr.reason}` })
        }
      }
      for (const ev of inbound.value.events) {
        const view0 = buildReplyOwnershipView(ev, undefined)
        const relationship = view0.actionKey ? enrichmentByKey.get(`${ev.platform}:${view0.actionKey.split(':').slice(2).join(':')}`) : undefined
        const row = view0.actionKey && deps.ledger ? await deps.ledger.get(view0.actionKey) : undefined
        const view = buildReplyOwnershipView(ev, row && 'actionKey' in row ? row : undefined, { relationship })
        replyOwnership.push(view)
        if (view.status === 'awaiting_approval') {
          // Intelligence may raise how soon a human should look; it never changes who executes or what is allowed.
          attentionRaw.push({ sourceSystem: 'my-sns', sourceEntityId: ev.eventId, sourceEntityType: 'inbound_event', kind: 'approval', summary: view.line, priority: view.relationship?.priority === 'high' ? 'high' : 'normal', createdAt: ev.receivedAt })
        }
      }
    } else if (inbound.httpStatus !== 404 && inbound.reason !== 'not_configured') {
      unreadable.push({ system: 'my-sns', reason: `inbound-events: ${inbound.reason}` })
    }
  }

  // Unknown outcomes are the most dangerous state: no system will resend, so a human must reconcile.
  if (deps.ledger) {
    for (const row of await deps.ledger.list({ state: 'OUTCOME_UNKNOWN' })) {
      attentionRaw.push({
        sourceSystem: 'artist-os',
        sourceEntityId: row.actionKey,
        sourceEntityType: 'action_ledger',
        kind: 'ambiguity',
        summary: `Reply outcome unknown (${row.actionKey}, owner ${row.ownerSystem}). Check the platform; no system will resend until you reconcile.`,
        priority: 'high',
        createdAt: row.updatedAt,
      })
    }
    for (const row of await deps.ledger.list({ state: 'EXECUTING' })) {
      running.push({ sourceSystem: row.ownerSystem as SystemId, sourceEntityId: row.actionKey, sourceEntityType: 'reply_action', summary: `Sending reply (${row.actionKey})`, status: 'executing', at: row.executingAt ?? row.updatedAt, actionCapability: 'none' })
    }
  }

  const attention = buildAttentionQueue(attentionRaw)
  unreadable.sort((a, b) => a.system.localeCompare(b.system))
  return {
    generatedAt: now,
    autoCompleted,
    running,
    needsYou: attention.map(fromAttention),
    scheduled,
    attention,
    replyOwnership,
    unreadableSources: unreadable,
  }
}
