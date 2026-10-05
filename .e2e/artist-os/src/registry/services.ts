import { z } from 'zod'
import { IsoTimestampSchema, SYSTEM_IDS, type SystemId, SystemIdSchema } from '../core/common.js'

/**
 * How Artist OS can reach a specialist:
 *  - remote: HTTPS baseUrl
 *  - local:  sibling process on this machine (baseUrl is localhost)
 *  - disabled: deliberately not integrated
 */
export const SERVICE_MODES = ['remote', 'local', 'disabled'] as const

/**
 * Observed status. `not_integrated` is distinct from `unavailable`:
 * the specialist exists but exposes no Artist OS read contract yet. We never
 * report `healthy` for something we have not actually probed.
 */
export const SERVICE_STATUSES = ['unknown', 'healthy', 'degraded', 'unavailable', 'not_integrated', 'disabled'] as const
export type ServiceStatus = (typeof SERVICE_STATUSES)[number]

export const ServiceDescriptorSchema = z.object({
  serviceId: SystemIdSchema,
  displayName: z.string(),
  domain: z.enum(['social', 'media', 'music', 'local']),
  mode: z.enum(SERVICE_MODES),
  baseUrl: z.url().optional(),
  status: z.enum(SERVICE_STATUSES),
  version: z.string().optional(),
  capabilities: z.array(z.string()).default([]),
  lastHealthyAt: IsoTimestampSchema.optional(),
  lastCheckedAt: IsoTimestampSchema.optional(),
  degradedReason: z.string().optional(),
  /** What this service is the source of truth for. Documentation, enforced by BOUNDARY tests. */
  sourceOfTruthFor: z.array(z.string()),
})
export type ServiceDescriptor = z.infer<typeof ServiceDescriptorSchema>

export const SERVICE_CATALOG: Record<Exclude<SystemId, 'artist-os' | 'mac-runner'>, Pick<ServiceDescriptor, 'displayName' | 'domain' | 'sourceOfTruthFor'>> = {
  'my-sns': {
    displayName: 'My-SNS',
    domain: 'social',
    sourceOfTruthFor: ['brand_profile', 'seed', 'draft', 'revision', 'publish_job', 'social_oauth', 'inbox', 'reply_job'],
  },
  'sns-ai': { displayName: 'SNS-AI', domain: 'social', sourceOfTruthFor: ['social_research', 'social_strategy', 'content_candidates'] },
  'sns-providers': { displayName: 'SNS-providers', domain: 'social', sourceOfTruthFor: ['relationship', 'candidate', 'proactive_engagement'] },
  'growth-bridge': { displayName: 'SNS-Growth-Bridge', domain: 'social', sourceOfTruthFor: ['social_growth_learning', 'identity_link_contracts'] },
  'sns-hub': { displayName: 'SNS-HUB', domain: 'social', sourceOfTruthFor: ['public_cta_destination'] },
  'take-layer': { displayName: 'Take-Layer', domain: 'media', sourceOfTruthFor: ['song_memory', 'arrangement', 'timeline_sync', 'editing_preference'] },
  'my-spotify': { displayName: 'My-Spotify', domain: 'music', sourceOfTruthFor: ['artist_track_intelligence', 'listener_world', 'artist_playlist_lifecycle', 'music_campaign'] },
  'playlist-garden': { displayName: 'Playlist Garden', domain: 'music', sourceOfTruthFor: ['personal_playlist_garden'] },
}

export interface ServiceConfigEntry {
  mode?: (typeof SERVICE_MODES)[number]
  baseUrl?: string
}

/** Builds descriptors for every specialist. Anything without config is `disabled`/`unknown` — never assumed healthy. */
export function buildServiceDescriptors(config: Partial<Record<SystemId, ServiceConfigEntry>> = {}): ServiceDescriptor[] {
  return (Object.keys(SERVICE_CATALOG) as (keyof typeof SERVICE_CATALOG)[]).map((id) => {
    const entry = config[id]
    const meta = SERVICE_CATALOG[id]
    const configured = entry?.baseUrl && entry.mode !== 'disabled'
    return ServiceDescriptorSchema.parse({
      serviceId: id,
      ...meta,
      mode: entry?.mode ?? (configured ? 'remote' : 'disabled'),
      baseUrl: entry?.baseUrl,
      status: configured ? 'unknown' : 'disabled',
      capabilities: [],
    })
  })
}

export class ServiceRegistry {
  private readonly services = new Map<SystemId, ServiceDescriptor>()
  constructor(descriptors: ServiceDescriptor[]) {
    for (const d of descriptors) this.services.set(d.serviceId, d)
  }
  get(id: SystemId): ServiceDescriptor | undefined {
    return this.services.get(id)
  }
  list(): ServiceDescriptor[] {
    return SYSTEM_IDS.flatMap((id) => (this.services.has(id) ? [this.services.get(id)!] : []))
  }
  update(id: SystemId, patch: Partial<ServiceDescriptor>): ServiceDescriptor {
    const cur = this.services.get(id)
    if (!cur) throw new Error(`unknown service ${id}`)
    const next = ServiceDescriptorSchema.parse({ ...cur, ...patch, serviceId: id })
    this.services.set(id, next)
    return next
  }
}
