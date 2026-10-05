import { z } from 'zod'
import {
  type Clock,
  type IdGenerator,
  IsoTimestampSchema,
  OpaqueIdSchema,
  SCHEMA_VERSION,
  type SourceRef,
  SourceRefSchema,
  randomIdGenerator,
  sourceRefKey,
  systemClock,
} from './common.js'

/**
 * Identity Graph: explicit links between existing source-of-truth ids.
 * Specialist ids are never replaced. Links are NEVER inferred from handle,
 * title or display name alone.
 */
export const LINK_STATUSES = ['proposed', 'confirmed', 'rejected', 'revoked'] as const
export type LinkStatus = (typeof LINK_STATUSES)[number]

/** How the link was established. `*_match` evidence is weak and can never auto-confirm. */
export const LINK_EVIDENCE_KINDS = [
  'human_confirmed',
  'shared_strong_identifier', // e.g. identical ISRC / MusicBrainz recording id reported by both sources
  'source_attested', // a specialist system explicitly declared the mapping
  'title_match',
  'handle_match',
  'display_name_match',
] as const
export type LinkEvidenceKind = (typeof LINK_EVIDENCE_KINDS)[number]

export const WEAK_EVIDENCE: ReadonlySet<LinkEvidenceKind> = new Set([
  'title_match',
  'handle_match',
  'display_name_match',
])

export const IdentityLinkSchema = z.object({
  schemaVersion: z.literal(SCHEMA_VERSION),
  linkId: OpaqueIdSchema,
  /** The Artist OS entity (Release, ArtistTrackRef, ...) this link hangs off. */
  artistOsRef: SourceRefSchema,
  /** The specialist-owned entity being linked. */
  target: SourceRefSchema,
  status: z.enum(LINK_STATUSES),
  evidence: z.enum(LINK_EVIDENCE_KINDS),
  note: z.string().max(500).optional(),
  confidence: z.number().min(0).max(1),
  createdAt: IsoTimestampSchema,
  confirmedAt: IsoTimestampSchema.optional(),
  confirmedBy: OpaqueIdSchema.optional(),
})
export type IdentityLink = z.infer<typeof IdentityLinkSchema>

export class IdentityError extends Error {
  constructor(
    readonly code: 'WEAK_EVIDENCE_CANNOT_CONFIRM' | 'LINK_NOT_FOUND' | 'DUPLICATE_LINK' | 'CONFLICTING_CONFIRMED_LINK' | 'INVALID_TRANSITION',
    message: string,
  ) {
    super(message)
    this.name = 'IdentityError'
  }
}

export interface IdentityGraphDeps {
  clock?: Clock
  ids?: IdGenerator
}

/**
 * In-memory Identity Graph. Persistence is an adapter concern; this class owns the rules.
 */
export class IdentityGraph {
  private readonly links = new Map<string, IdentityLink>()
  private readonly clock: Clock
  private readonly ids: IdGenerator

  constructor(deps: IdentityGraphDeps = {}) {
    this.clock = deps.clock ?? systemClock
    this.ids = deps.ids ?? randomIdGenerator
  }

  /** Records a link proposal. Never confirmed implicitly. */
  propose(input: {
    artistOsRef: SourceRef
    target: SourceRef
    evidence: LinkEvidenceKind
    confidence: number
    note?: string
  }): IdentityLink {
    const dupe = this.find(input.artistOsRef, input.target)
    if (dupe && (dupe.status === 'proposed' || dupe.status === 'confirmed')) {
      throw new IdentityError('DUPLICATE_LINK', `link already ${dupe.status}: ${dupe.linkId}`)
    }
    const link = IdentityLinkSchema.parse({
      schemaVersion: SCHEMA_VERSION,
      linkId: this.ids('lnk'),
      artistOsRef: input.artistOsRef,
      target: input.target,
      status: 'proposed',
      evidence: input.evidence,
      note: input.note,
      confidence: input.confidence,
      createdAt: this.clock().toISOString(),
    })
    this.links.set(link.linkId, link)
    return link
  }

  /**
   * Confirms a proposed link. Requires an explicit actor (a human or an
   * attesting system). Weak evidence (title/handle/display-name) can only be
   * confirmed by a human, never by a system actor.
   */
  confirm(linkId: string, actor: { kind: 'human' | 'system'; id: string }): IdentityLink {
    const link = this.mustGet(linkId)
    if (link.status !== 'proposed') {
      throw new IdentityError('INVALID_TRANSITION', `cannot confirm a ${link.status} link`)
    }
    if (WEAK_EVIDENCE.has(link.evidence) && actor.kind !== 'human') {
      throw new IdentityError('WEAK_EVIDENCE_CANNOT_CONFIRM', `${link.evidence} evidence needs human confirmation`)
    }
    const other = this.confirmedTargetsFor(link.artistOsRef, link.target.system, link.target.entityType).find(
      (l) => l.linkId !== link.linkId && l.target.entityId !== link.target.entityId,
    )
    if (other) {
      throw new IdentityError(
        'CONFLICTING_CONFIRMED_LINK',
        `${sourceRefKey(link.artistOsRef)} already confirmed to ${sourceRefKey(other.target)}; revoke it first`,
      )
    }
    const next: IdentityLink = { ...link, status: 'confirmed', confirmedAt: this.clock().toISOString(), confirmedBy: actor.id }
    this.links.set(linkId, next)
    return next
  }

  reject(linkId: string): IdentityLink {
    const link = this.mustGet(linkId)
    if (link.status !== 'proposed') throw new IdentityError('INVALID_TRANSITION', `cannot reject a ${link.status} link`)
    const next = { ...link, status: 'rejected' as const }
    this.links.set(linkId, next)
    return next
  }

  revoke(linkId: string): IdentityLink {
    const link = this.mustGet(linkId)
    if (link.status !== 'confirmed') throw new IdentityError('INVALID_TRANSITION', `cannot revoke a ${link.status} link`)
    const next = { ...link, status: 'revoked' as const }
    this.links.set(linkId, next)
    return next
  }

  /** Only CONFIRMED links are authoritative for resolution. */
  resolve(artistOsRef: SourceRef, system?: SourceRef['system']): IdentityLink[] {
    const key = sourceRefKey(artistOsRef)
    return [...this.links.values()].filter(
      (l) => l.status === 'confirmed' && sourceRefKey(l.artistOsRef) === key && (!system || l.target.system === system),
    )
  }

  /** Reverse lookup: which Artist OS entities is this specialist entity confirmed to belong to? */
  reverse(target: SourceRef): IdentityLink[] {
    const key = sourceRefKey(target)
    return [...this.links.values()].filter((l) => l.status === 'confirmed' && sourceRefKey(l.target) === key)
  }

  /**
   * Detects identity mismatches: one specialist entity confirmed under several
   * Artist OS entities, or one Artist OS entity with several confirmed targets of the
   * same (system, entityType). Both must be resolved by a human.
   */
  findConflicts(): { kind: 'target_shared' | 'multiple_targets'; links: IdentityLink[] }[] {
    const confirmed = [...this.links.values()].filter((l) => l.status === 'confirmed')
    const out: { kind: 'target_shared' | 'multiple_targets'; links: IdentityLink[] }[] = []
    const byTarget = new Map<string, IdentityLink[]>()
    const bySlot = new Map<string, IdentityLink[]>()
    for (const l of confirmed) {
      const tk = sourceRefKey(l.target)
      byTarget.set(tk, [...(byTarget.get(tk) ?? []), l])
      const sk = `${sourceRefKey(l.artistOsRef)}|${l.target.system}:${l.target.entityType}`
      bySlot.set(sk, [...(bySlot.get(sk) ?? []), l])
    }
    for (const group of byTarget.values()) {
      if (new Set(group.map((l) => sourceRefKey(l.artistOsRef))).size > 1) out.push({ kind: 'target_shared', links: group })
    }
    for (const group of bySlot.values()) {
      if (group.length > 1) out.push({ kind: 'multiple_targets', links: group })
    }
    return out
  }

  list(): IdentityLink[] {
    return [...this.links.values()]
  }

  /** Rebuilds from persisted links. Every link is re-validated; a corrupt file fails loudly rather than being half-loaded. */
  restore(links: readonly unknown[]): void {
    const parsed = links.map((l) => IdentityLinkSchema.parse(l))
    this.links.clear()
    for (const l of parsed) this.links.set(l.linkId, l)
  }

  private find(a: SourceRef, t: SourceRef): IdentityLink | undefined {
    const ak = sourceRefKey(a)
    const tk = sourceRefKey(t)
    return [...this.links.values()].find((l) => sourceRefKey(l.artistOsRef) === ak && sourceRefKey(l.target) === tk)
  }

  private confirmedTargetsFor(a: SourceRef, system: SourceRef['system'], entityType: string): IdentityLink[] {
    const ak = sourceRefKey(a)
    return [...this.links.values()].filter(
      (l) => l.status === 'confirmed' && sourceRefKey(l.artistOsRef) === ak && l.target.system === system && l.target.entityType === entityType,
    )
  }

  private mustGet(linkId: string): IdentityLink {
    const l = this.links.get(linkId)
    if (!l) throw new IdentityError('LINK_NOT_FOUND', linkId)
    return l
  }
}
