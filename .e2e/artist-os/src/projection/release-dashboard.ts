import type { ActivityItem } from '../contracts/service.js'
import { type SourceRef, sourceRefKey } from '../core/common.js'
import type { IdentityGraph } from '../core/identity.js'
import { RELEASE_DOMAIN_SLOTS, type Release, releaseRefOf } from '../core/release.js'
import type { AttentionEntry } from './attention.js'

export type DomainName = (typeof RELEASE_DOMAIN_SLOTS)[number]['domain']

export interface SlotView {
  system: SourceRef['system']
  entityType: string
  /** Confirmed links only. */
  linked: SourceRef[]
  /** Proposed-but-unconfirmed links: shown so a human can confirm, never treated as truth. */
  pendingConfirmation: number
  state: 'linked' | 'not_linked' | 'needs_confirmation'
}

export interface ReleaseDashboard {
  release: Release
  domains: Record<DomainName, { slots: SlotView[]; activity: ActivityItem[]; attention: AttentionEntry[] }>
  attention: AttentionEntry[]
  identityConflicts: number
}

/**
 * Release dashboard. Joins by CONFIRMED identity links only: an attention/activity item
 * appears under a release only when its source entity is a confirmed link target.
 * No fuzzy matching by title/handle, ever.
 */
export function buildReleaseDashboard(
  release: Release,
  graph: IdentityGraph,
  feed: { attention: readonly AttentionEntry[]; activity: readonly ActivityItem[] },
): ReleaseDashboard {
  const ref = releaseRefOf(release)
  const confirmed = graph.resolve(ref)
  const pending = graph.list().filter((l) => l.status === 'proposed' && sourceRefKey(l.artistOsRef) === sourceRefKey(ref))
  const linkedKeys = new Set(confirmed.map((l) => sourceRefKey(l.target)))

  const domains = {} as ReleaseDashboard['domains']
  for (const slot of RELEASE_DOMAIN_SLOTS) {
    const d = (domains[slot.domain] ??= { slots: [], activity: [], attention: [] })
    const linked = confirmed.filter((l) => l.target.system === slot.system && l.target.entityType === slot.entityType).map((l) => l.target)
    const pend = pending.filter((l) => l.target.system === slot.system && l.target.entityType === slot.entityType).length
    d.slots.push({
      system: slot.system,
      entityType: slot.entityType,
      linked,
      pendingConfirmation: pend,
      state: linked.length > 0 ? 'linked' : pend > 0 ? 'needs_confirmation' : 'not_linked',
    })
  }
  const keyOfItem = (i: { sourceSystem: SourceRef['system']; sourceEntityType: string; sourceEntityId: string }) =>
    sourceRefKey({ system: i.sourceSystem, entityType: i.sourceEntityType, entityId: i.sourceEntityId })
  const domainOfSystem = (sys: SourceRef['system'], type: string) => RELEASE_DOMAIN_SLOTS.find((s) => s.system === sys && s.entityType === type)?.domain
  const attention: AttentionEntry[] = []
  for (const a of feed.attention) {
    if (!linkedKeys.has(keyOfItem(a))) continue
    attention.push(a)
    const dom = domainOfSystem(a.sourceSystem, a.sourceEntityType)
    if (dom) domains[dom]?.attention.push(a)
  }
  for (const a of feed.activity) {
    if (!linkedKeys.has(keyOfItem(a))) continue
    const dom = domainOfSystem(a.sourceSystem, a.sourceEntityType)
    if (dom) domains[dom]?.activity.push(a)
  }
  const conflicts = graph.findConflicts().filter((c) => c.links.some((l) => sourceRefKey(l.artistOsRef) === sourceRefKey(ref))).length
  return { release, domains, attention, identityConflicts: conflicts }
}
