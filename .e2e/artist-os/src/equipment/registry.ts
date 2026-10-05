import { z } from 'zod'
import { IsoTimestampSchema } from '../core/common.js'

export const EQUIPMENT_STATES = [
  'UNAVAILABLE',
  'AVAILABLE',
  'NOT_CONNECTED',
  'CONNECTED_FREE',
  'CONNECTED_TRIAL',
  'CONNECTED_PAID',
  'PAYMENT_REQUIRED',
  'QUOTA_LOW',
  'QUOTA_EXHAUSTED',
  'AUTH_REQUIRED',
  'DEGRADED',
] as const
export type EquipmentState = (typeof EQUIPMENT_STATES)[number]

export const CONNECTION_TYPES = ['REMOTE_MCP', 'REST_WEBHOOK', 'EXTERNAL_HANDOFF'] as const
export type ConnectionType = (typeof CONNECTION_TYPES)[number]

/** Routing cost tiers, cheapest first: LOCAL → FREE → ALREADY_PAID → OPTIONAL_PAID. */
export const COST_TIERS = ['LOCAL', 'FREE', 'ALREADY_PAID', 'OPTIONAL_PAID'] as const
export type CostTier = (typeof COST_TIERS)[number]

/** Hard billing rule. Present on every record so it cannot be configured away. */
export const BILLING_POLICY = 'NEVER_AUTO_PURCHASE' as const

export const EquipmentSchema = z.object({
  equipmentId: z.string().regex(/^[a-z0-9_-]+$/),
  displayName: z.string(),
  connectionType: z.enum(CONNECTION_TYPES),
  capabilities: z.array(z.string()).min(1),
  /** Equipment in the same group are alternatives; avoid calling several paid ones for the same need. */
  competitionGroup: z.string().optional(),
  state: z.enum(EQUIPMENT_STATES),
  stateReason: z.string().max(300).optional(),
  stateUpdatedAt: IsoTimestampSchema.optional(),
  billingPolicy: z.literal(BILLING_POLICY),
  /** Whether using it (when connected) costs money on top of what is already paid. */
  paid: z.boolean(),
  setupNote: z.string().optional(),
})
export type Equipment = z.infer<typeof EquipmentSchema>

const CATALOG: Omit<Equipment, 'state' | 'billingPolicy'>[] = [
  { equipmentId: 'vidiq', displayName: 'vidIQ', connectionType: 'REMOTE_MCP', capabilities: ['youtube.market_research', 'youtube.title_optimization', 'creative.thumbnail_intel'], paid: true },
  { equipmentId: 'metricool', displayName: 'Metricool', connectionType: 'REMOTE_MCP', capabilities: ['social.best_post_time', 'social.cross_analytics'], paid: true },
  { equipmentId: 'canva', displayName: 'Canva', connectionType: 'REMOTE_MCP', capabilities: ['creative.thumbnail', 'creative.playlist_cover'], paid: true },
  { equipmentId: 'soundcharts', displayName: 'Soundcharts', connectionType: 'REMOTE_MCP', capabilities: ['music.market_intelligence'], competitionGroup: 'music_market_intelligence', paid: true },
  { equipmentId: 'songstats', displayName: 'Songstats', connectionType: 'REST_WEBHOOK', capabilities: ['music.market_intelligence', 'music.cross_platform_analytics'], competitionGroup: 'music_market_intelligence', paid: true },
  { equipmentId: 'chartmetric', displayName: 'Chartmetric', connectionType: 'REST_WEBHOOK', capabilities: ['music.market_intelligence'], competitionGroup: 'music_market_intelligence', paid: true },
  { equipmentId: 'norder', displayName: 'NORDER', connectionType: 'EXTERNAL_HANDOFF', capabilities: ['music.market_intelligence', 'music.artist_manager_intel'], competitionGroup: 'music_market_intelligence', paid: true, setupNote: 'No supported developer interface yet; human handoff only.' },
  { equipmentId: 'bandsintown', displayName: 'Bandsintown', connectionType: 'REST_WEBHOOK', capabilities: ['live.events', 'fan.signals'], paid: false },
  { equipmentId: 'feature_fm', displayName: 'Feature.fm', connectionType: 'REST_WEBHOOK', capabilities: ['release.smart_link'], paid: true },
]

/** States in which a capability may be considered usable without human action. */
const USABLE_STATES: ReadonlySet<EquipmentState> = new Set(['CONNECTED_FREE', 'CONNECTED_TRIAL', 'CONNECTED_PAID', 'QUOTA_LOW'])
export const isUsableState = (s: EquipmentState) => USABLE_STATES.has(s)

/** States needing a human (billing/auth) → surfaced as Attention, never auto-resolved. */
export const NEEDS_HUMAN_STATES: ReadonlySet<EquipmentState> = new Set(['PAYMENT_REQUIRED', 'AUTH_REQUIRED', 'QUOTA_EXHAUSTED'])

export class EquipmentRegistry {
  private readonly items = new Map<string, Equipment>()

  /** Default catalog: EVERYTHING starts NOT_CONNECTED, so Artist OS boots with zero equipment. */
  static withDefaultCatalog(): EquipmentRegistry {
    const r = new EquipmentRegistry()
    for (const c of CATALOG) r.register({ ...c, state: 'NOT_CONNECTED', billingPolicy: BILLING_POLICY })
    return r
  }

  register(e: Equipment): void {
    this.items.set(e.equipmentId, EquipmentSchema.parse(e))
  }
  get(id: string) {
    return this.items.get(id)
  }
  list() {
    return [...this.items.values()]
  }

  /**
   * Records an observed state. Upgrading to a paid state requires the human to have
   * performed the purchase out-of-band; this method only RECORDS what was observed.
   * There is intentionally no `purchase`/`subscribe`/`upgrade` method anywhere.
   */
  setState(id: string, state: EquipmentState, reason: string | undefined, at: Date): Equipment {
    const cur = this.items.get(id)
    if (!cur) throw new Error(`unknown equipment ${id}`)
    const next = EquipmentSchema.parse({ ...cur, state, stateReason: reason, stateUpdatedAt: at.toISOString() })
    this.items.set(id, next)
    return next
  }
}
