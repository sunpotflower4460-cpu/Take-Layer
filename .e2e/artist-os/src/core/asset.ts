import { z } from 'zod'
import { IsoTimestampSchema, OpaqueIdSchema, SCHEMA_VERSION, SystemIdSchema } from './common.js'

export const ASSET_LOCATION_TYPES = ['my-sns-storage', 'take-layer-local', 'runner-local', 'external'] as const
export const ASSET_KINDS = [
  'raw_video',
  'raw_audio',
  'master_wav',
  'lyrics',
  'derived_video',
  'derived_audio',
  'thumbnail',
  'artifact_json',
  'image',
  'other',
] as const

/**
 * Cross-domain asset reference. Artist OS keeps references/metadata, never the bytes.
 * Cloud systems must not need a raw Mac filesystem path: for runner-local assets
 * `locationId` is an opaque runner-local identifier, and `runnerId` names the owner.
 */
export const AssetRefSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    assetRef: OpaqueIdSchema,
    ownerSystem: SystemIdSchema,
    kind: z.enum(ASSET_KINDS),
    locationType: z.enum(ASSET_LOCATION_TYPES),
    /** Opaque id inside the location (storage key, runner-local asset id, URL for `external`). */
    locationId: OpaqueIdSchema,
    runnerId: OpaqueIdSchema.optional(),
    contentHash: z.string().regex(/^sha256:[0-9a-f]{64}$/).optional(),
    size: z.number().int().nonnegative().optional(),
    mimeType: z.string().max(128).optional(),
    derivedFrom: z.array(OpaqueIdSchema).max(50).default([]),
    generator: z.string().max(128).optional(),
    generatorVersion: z.string().max(64).optional(),
    createdAt: IsoTimestampSchema,
  })
  .superRefine((v, ctx) => {
    if (v.locationType === 'runner-local' && !v.runnerId) {
      ctx.addIssue({ code: 'custom', path: ['runnerId'], message: 'runner-local assets must name their runnerId' })
    }
    // A raw filesystem path must never leak into the cloud-visible reference.
    if (v.locationType === 'runner-local' && /^(\/|[A-Za-z]:\\|~)/.test(v.locationId)) {
      ctx.addIssue({ code: 'custom', path: ['locationId'], message: 'runner-local locationId must be opaque, not a filesystem path' })
    }
  })
export type AssetRef = z.infer<typeof AssetRefSchema>
