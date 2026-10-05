import { type CostTier, type Equipment, type EquipmentRegistry, isUsableState } from './registry.js'

/** Capabilities Artist OS or a specialist can satisfy itself, without any vendor. */
export interface LocalCapability {
  capability: string
  tier: Extract<CostTier, 'LOCAL' | 'FREE'>
  /** Which in-house system provides it, for display only. */
  provider: string
  available: boolean
}

export type RouteDecision =
  | { kind: 'local'; capability: string; provider: string; tier: 'LOCAL' | 'FREE' }
  | { kind: 'equipment'; capability: string; equipmentId: string; tier: CostTier }
  | { kind: 'handoff'; capability: string; equipmentId: string; reason: string }
  | { kind: 'needs_human'; capability: string; equipmentId: string; reason: 'PAYMENT_REQUIRED' | 'AUTH_REQUIRED' | 'QUOTA_EXHAUSTED'; message: string }
  | { kind: 'unavailable'; capability: string; reason: string }

function tierOf(e: Equipment): CostTier {
  if (!e.paid) return 'FREE'
  return e.state === 'CONNECTED_PAID' ? 'ALREADY_PAID' : e.state === 'CONNECTED_TRIAL' || e.state === 'CONNECTED_FREE' ? 'FREE' : 'OPTIONAL_PAID'
}
const TIER_RANK: Record<CostTier, number> = { LOCAL: 0, FREE: 1, ALREADY_PAID: 2, OPTIONAL_PAID: 3 }

/**
 * Capability Router. Callers ask for a CAPABILITY, never a vendor.
 * Preference: LOCAL → FREE → ALREADY_PAID → OPTIONAL_PAID. Equipment that would
 * require a new purchase (OPTIONAL_PAID: connected state unknown/paid-needed) is
 * never selected automatically — it is reported as `needs_human`.
 * Degrades safely: no equipment ⇒ `unavailable`, never an exception.
 */
export class CapabilityRouter {
  constructor(
    private readonly equipment: EquipmentRegistry,
    private readonly locals: readonly LocalCapability[] = [],
  ) {}

  route(capability: string): RouteDecision {
    const local = this.locals.find((l) => l.capability === capability && l.available)
    if (local) return { kind: 'local', capability, provider: local.provider, tier: local.tier }

    const candidates = this.equipment.list().filter((e) => e.capabilities.includes(capability))
    if (candidates.length === 0) return { kind: 'unavailable', capability, reason: 'no equipment declares this capability' }

    const usable = candidates.filter((e) => e.connectionType !== 'EXTERNAL_HANDOFF' && isUsableState(e.state))
    if (usable.length > 0) {
      // Pick exactly ONE per call (avoid duplicate paid calls within a competition group).
      const best = [...usable].sort((a, b) => TIER_RANK[tierOf(a)] - TIER_RANK[tierOf(b)] || a.equipmentId.localeCompare(b.equipmentId))[0]!
      return { kind: 'equipment', capability, equipmentId: best.equipmentId, tier: tierOf(best) }
    }

    const blocked = candidates.find((e) => e.state === 'PAYMENT_REQUIRED' || e.state === 'AUTH_REQUIRED' || e.state === 'QUOTA_EXHAUSTED')
    if (blocked) {
      const reason = blocked.state as 'PAYMENT_REQUIRED' | 'AUTH_REQUIRED' | 'QUOTA_EXHAUSTED'
      return { kind: 'needs_human', capability, equipmentId: blocked.equipmentId, reason, message: `${blocked.displayName}: ${reason}. A human must act; Artist OS never purchases or upgrades.` }
    }
    const handoff = candidates.find((e) => e.connectionType === 'EXTERNAL_HANDOFF')
    if (handoff) return { kind: 'handoff', capability, equipmentId: handoff.equipmentId, reason: 'no machine interface; human handoff' }

    return { kind: 'unavailable', capability, reason: `equipment not connected (${candidates.map((c) => c.displayName).join(', ')})` }
  }
}
