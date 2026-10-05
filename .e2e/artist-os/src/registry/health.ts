import { z } from 'zod'
import type { SpecialistClient } from '../clients/base.js'
import { LEGACY_HEALTH_PATHS, NO_HTTP_SURFACE } from '../clients/specialists.js'
import type { Clock, SystemId } from '../core/common.js'
import { type ServiceDescriptor, type ServiceRegistry, type ServiceStatus } from './services.js'

export interface HealthProbeResult {
  serviceId: SystemId
  status: ServiceStatus
  reason?: string
}

/**
 * Probes one specialist. Order:
 *  1. Artist OS contract health  → healthy / degraded
 *  2. else legacy shipped health route (reachability only) → not_integrated
 *  3. else unavailable (or not_integrated if the service has no HTTP surface at all)
 * Never reports `healthy` without a valid contract response.
 */
export async function probeService(client: SpecialistClient, descriptor: ServiceDescriptor, clock: Clock): Promise<{ result: HealthProbeResult; patch: Partial<ServiceDescriptor> }> {
  const id = descriptor.serviceId
  const now = clock().toISOString()
  if (descriptor.mode === 'disabled' || !descriptor.baseUrl) {
    if (NO_HTTP_SURFACE.has(id)) {
      return mk(id, 'not_integrated', 'no HTTP surface; file/Git/Runner transport only', now)
    }
    return mk(id, 'disabled', 'not configured', now, false)
  }
  const h = await client.health()
  if (h.ok) {
    const status: ServiceStatus = h.value.status === 'unavailable' ? 'unavailable' : h.value.status
    return {
      result: { serviceId: id, status, reason: h.value.degradedReason },
      patch: {
        status,
        version: h.value.version,
        capabilities: h.value.capabilities,
        degradedReason: h.value.degradedReason,
        lastCheckedAt: now,
        ...(status === 'healthy' ? { lastHealthyAt: now } : {}),
      },
    }
  }
  if (h.reason === 'contract_mismatch' || h.reason === 'invalid_response') {
    return mk(id, 'degraded', `contract violation: ${h.detail}`, now)
  }
  const legacy = LEGACY_HEALTH_PATHS[id]
  // The contract route is absent/unauthorized but a shipped health route may still answer:
  // that proves reachability only, so the service is `not_integrated`, never `healthy`.
  if (legacy && h.reason !== 'timeout' && h.reason !== 'network' && h.reason !== 'not_configured') {
    const l = await client.getJson(legacy, z.unknown(), false)
    if (l.ok) return mk(id, 'not_integrated', 'reachable, but no Artist OS service contract yet', now)
  }
  return mk(id, 'unavailable', `${h.reason}: ${h.detail}`, now)
}

function mk(id: SystemId, status: ServiceStatus, reason: string, at: string, checked = true) {
  return {
    result: { serviceId: id, status, reason } as HealthProbeResult,
    patch: { status, degradedReason: reason, lastCheckedAt: checked ? at : undefined } as Partial<ServiceDescriptor>,
  }
}

export interface HealthReport {
  checkedAt: string
  overall: 'ok' | 'degraded' | 'attention'
  services: HealthProbeResult[]
}

export async function aggregateHealth(registry: ServiceRegistry, clients: Map<SystemId, SpecialistClient>, clock: Clock): Promise<HealthReport> {
  const results: HealthProbeResult[] = []
  await Promise.all(
    registry.list().map(async (d) => {
      const client = clients.get(d.serviceId)
      if (!client) return
      const { result, patch } = await probeService(client, d, clock)
      registry.update(d.serviceId, patch)
      results.push(result)
    }),
  )
  results.sort((a, b) => a.serviceId.localeCompare(b.serviceId))
  // Disabled / not_integrated are normal in early v2 and do not make the system "degraded";
  // only configured services that fail do.
  const bad = results.some((r) => r.status === 'unavailable' || r.status === 'degraded')
  return { checkedAt: clock().toISOString(), overall: bad ? 'degraded' : 'ok', services: results }
}
