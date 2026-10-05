import { z } from 'zod'

/**
 * Every persisted/exchanged Artist OS record carries an explicit schemaVersion
 * so it can evolve without silently breaking readers.
 */
export const SCHEMA_VERSION = 1 as const

/** Source systems Artist OS coordinates. Artist OS itself is `artist-os`. */
export const SYSTEM_IDS = [
  'artist-os',
  'my-sns',
  'sns-ai',
  'sns-providers',
  'growth-bridge',
  'sns-hub',
  'take-layer',
  'my-spotify',
  'playlist-garden',
  'mac-runner',
] as const
export type SystemId = (typeof SYSTEM_IDS)[number]
export const SystemIdSchema = z.enum(SYSTEM_IDS)

/** A non-empty, trimmed opaque id. Artist OS never interprets specialist ids. */
export const OpaqueIdSchema = z.string().trim().min(1).max(256)

export const IsoTimestampSchema = z.iso.datetime({ offset: true })

/**
 * Reference to an entity owned by a specialist system. Artist OS stores
 * references, never copies of the entity.
 */
export const SourceRefSchema = z.object({
  system: SystemIdSchema,
  entityType: z.string().trim().min(1).max(64),
  entityId: OpaqueIdSchema,
})
export type SourceRef = z.infer<typeof SourceRefSchema>

export function sourceRefKey(ref: SourceRef): string {
  return `${ref.system}:${ref.entityType}:${ref.entityId}`
}

export type Clock = () => Date
export const systemClock: Clock = () => new Date()

export type IdGenerator = (prefix: string) => string
export const randomIdGenerator: IdGenerator = (prefix) => `${prefix}_${crypto.randomUUID()}`
