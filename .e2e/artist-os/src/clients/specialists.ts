import type { SystemId } from '../core/common.js'
import { type ClientResult, SpecialistClient, type SpecialistClientOptions } from './base.js'
import { type InboundEventsReport, InboundEventsReportSchema } from '../contracts/inbound.js'
import { type RelationshipEnrichmentReport, RelationshipEnrichmentReportSchema } from '../contracts/relationship.js'

/**
 * One bounded client per specialist. They share the read contract; per-service
 * knowledge (legacy health path) lives here so the rest of Artist OS never
 * hard-codes a specialist's URL layout.
 *
 * `legacyHealthPath` = an existing, already-shipped, unauthenticated health route.
 * It proves reachability only; it is NOT the Artist OS contract, so such a service
 * is reported `not_integrated`, never `healthy`.
 */
export const LEGACY_HEALTH_PATHS: Partial<Record<SystemId, string>> = {
  'sns-providers': '/api/health',
  'my-spotify': '/api/health',
  'playlist-garden': '/api/health',
  'sns-hub': '/_health/content-version',
}

/**
 * Specialists with NO HTTP surface today (SNS-AI: CLI + GitHub Actions + files;
 * Growth-Bridge: library; Take-Layer: iOS app). Artist OS must not pretend to reach
 * them over HTTP. They integrate through a file/Git/Runner transport (see INTEGRATION_GAPS).
 */
export const NO_HTTP_SURFACE: ReadonlySet<SystemId> = new Set<SystemId>(['sns-ai', 'growth-bridge', 'take-layer'])

export class MySnsClient extends SpecialistClient {
  /**
   * Read-only inbound events from the canonical inbound owner. A 404 means "contract not deployed here yet"
   * and is returned as such (callers treat it as absent, not as an outage).
   */
  inboundEvents(): Promise<ClientResult<InboundEventsReport>> {
    return this.getJson('/api/service/v1/inbound-events', InboundEventsReportSchema, true)
  }
}
export class SnsAiClient extends SpecialistClient {}
export class SnsProvidersClient extends SpecialistClient {
  /**
   * Read-only relationship intelligence about My-SNS-owned inbound events. Needs a READ-scoped token (not the
   * write-capable sync token). A 404 means managed mode / the route is not enabled there: not an outage.
   */
  relationshipEnrichment(): Promise<ClientResult<RelationshipEnrichmentReport>> {
    return this.getJson('/api/service/v1/relationship-enrichment', RelationshipEnrichmentReportSchema, true)
  }
}
export class GrowthBridgeClient extends SpecialistClient {}
export class SnsHubClient extends SpecialistClient {}
export class TakeLayerClient extends SpecialistClient {}
export class MySpotifyClient extends SpecialistClient {}
export class PlaylistGardenClient extends SpecialistClient {}

type ClientCtor = new (o: SpecialistClientOptions) => SpecialistClient
const CTORS: Partial<Record<SystemId, ClientCtor>> = {
  'my-sns': MySnsClient,
  'sns-ai': SnsAiClient,
  'sns-providers': SnsProvidersClient,
  'growth-bridge': GrowthBridgeClient,
  'sns-hub': SnsHubClient,
  'take-layer': TakeLayerClient,
  'my-spotify': MySpotifyClient,
  'playlist-garden': PlaylistGardenClient,
}

export interface ClientConfigEntry {
  baseUrl?: string
  token?: string
}

export function buildClients(
  config: Partial<Record<SystemId, ClientConfigEntry>>,
  shared: Pick<SpecialistClientOptions, 'fetchImpl' | 'timeoutMs'> = {},
): Map<SystemId, SpecialistClient> {
  const out = new Map<SystemId, SpecialistClient>()
  for (const [id, Ctor] of Object.entries(CTORS) as [SystemId, ClientCtor][]) {
    out.set(id, new Ctor({ service: id, ...config[id], ...shared }))
  }
  return out
}

/** Reads per-service config from env: ARTIST_OS_<SERVICE>_URL / _TOKEN. Missing ⇒ service stays disabled. */
export function clientConfigFromEnv(env: Record<string, string | undefined>): Partial<Record<SystemId, ClientConfigEntry>> {
  const out: Partial<Record<SystemId, ClientConfigEntry>> = {}
  for (const id of Object.keys(CTORS) as SystemId[]) {
    const key = id.toUpperCase().replace(/-/g, '_')
    const baseUrl = env[`ARTIST_OS_${key}_URL`]
    if (baseUrl) out[id] = { baseUrl, token: env[`ARTIST_OS_${key}_TOKEN`] }
  }
  return out
}
