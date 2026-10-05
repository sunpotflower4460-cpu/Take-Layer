import { z } from 'zod'
import { IsoTimestampSchema, OpaqueIdSchema, SCHEMA_VERSION } from './common.js'

export const RELEASE_STATUSES = ['planning', 'in_production', 'scheduled', 'released', 'archived'] as const
export type ReleaseStatus = (typeof RELEASE_STATUSES)[number]

/**
 * Release is a canonical cross-domain entity owned by Artist OS.
 * It holds references (via the Identity Graph) to specialist entities:
 * ArtistTrack (My-Spotify), Song/Arrangement (Take-Layer), Seeds (My-SNS),
 * social campaign (SNS-AI), music-growth campaign (My-Spotify), playlists, etc.
 * It does not copy their data. Links live in the Identity Graph keyed by
 * { system:'artist-os', entityType:'release', entityId: releaseId }.
 */
export const ReleaseSchema = z.object({
  schemaVersion: z.literal(SCHEMA_VERSION),
  releaseId: OpaqueIdSchema,
  workspaceRef: OpaqueIdSchema,
  title: z.string().trim().min(1).max(200),
  status: z.enum(RELEASE_STATUSES),
  releaseDate: z.iso.date().optional(),
  goalId: OpaqueIdSchema.optional(),
  /** Standard identifiers; informational, used as STRONG identity evidence only when both sources report them. */
  isrc: z.string().regex(/^[A-Z]{2}[A-Z0-9]{3}\d{7}$/).optional(),
  createdAt: IsoTimestampSchema,
  updatedAt: IsoTimestampSchema,
})
export type Release = z.infer<typeof ReleaseSchema>

export const releaseRefOf = (r: Pick<Release, 'releaseId'>) =>
  ({ system: 'artist-os', entityType: 'release', entityId: r.releaseId }) as const

/** Release link slots Artist OS expects to see in a healthy release. */
export const RELEASE_DOMAIN_SLOTS = [
  { domain: 'music', system: 'my-spotify', entityType: 'artist_track' },
  { domain: 'music', system: 'my-spotify', entityType: 'campaign' },
  { domain: 'media', system: 'take-layer', entityType: 'song' },
  { domain: 'social', system: 'my-sns', entityType: 'seed' },
  { domain: 'social', system: 'sns-ai', entityType: 'campaign' },
  { domain: 'distribution', system: 'sns-hub', entityType: 'hub_item' },
] as const

const TRANSITIONS: Record<ReleaseStatus, readonly ReleaseStatus[]> = {
  planning: ['in_production', 'archived'],
  in_production: ['scheduled', 'planning', 'archived'],
  scheduled: ['released', 'in_production', 'archived'],
  released: ['archived'],
  archived: [],
}
export const canTransitionRelease = (from: ReleaseStatus, to: ReleaseStatus) => TRANSITIONS[from].includes(to)
