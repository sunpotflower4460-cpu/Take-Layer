import { z } from 'zod'
import {
  type Clock,
  type IdGenerator,
  IsoTimestampSchema,
  OpaqueIdSchema,
  SCHEMA_VERSION,
  SourceRefSchema,
  SystemIdSchema,
  randomIdGenerator,
  systemClock,
} from './common.js'

/**
 * Operation Trace / event envelope. Answers "why did this post/edit/action happen?".
 * Stores decision SUMMARIES and evidence references, never model chain-of-thought.
 */
export const TraceEventSchema = z.object({
  schemaVersion: z.literal(SCHEMA_VERSION),
  eventId: OpaqueIdSchema,
  eventType: z.string().trim().min(1).max(128),
  producer: SystemIdSchema,
  occurredAt: IsoTimestampSchema,
  /** One trace per end-to-end story (e.g. Take-Layer proposal → ... → publish). */
  traceId: OpaqueIdSchema,
  /** Groups events of one logical operation. */
  correlationId: OpaqueIdSchema,
  /** The eventId that directly caused this one. */
  causationId: OpaqueIdSchema.optional(),
  workspaceRef: OpaqueIdSchema,
  subjectRefs: z.array(SourceRefSchema).max(50).default([]),
  /** Human-readable decision summary. Not model reasoning. */
  summary: z.string().max(500).default(''),
  payload: z.record(z.string(), z.unknown()).default({}),
})
export type TraceEvent = z.infer<typeof TraceEventSchema>

export interface TraceContext {
  traceId: string
  correlationId: string
  /** eventId of the event that caused whatever is about to be recorded. */
  causationId?: string
}

/** Persistence port for the Operation Trace (append-only). */
export interface TraceStore {
  append(event: TraceEvent): Promise<void>
  get(eventId: string): Promise<TraceEvent | undefined>
  byTrace(traceId: string): Promise<TraceEvent[]>
  all(limit?: number): Promise<TraceEvent[]>
}

export class MemoryTraceStore implements TraceStore {
  private readonly events = new Map<string, TraceEvent>()
  async append(e: TraceEvent) {
    if (this.events.has(e.eventId)) throw new Error(`trace event ${e.eventId} already exists (the trace is append-only)`)
    this.events.set(e.eventId, e)
  }
  async get(id: string) {
    return this.events.get(id)
  }
  async byTrace(traceId: string) {
    return [...this.events.values()].filter((e) => e.traceId === traceId).sort((a, b) => a.occurredAt.localeCompare(b.occurredAt))
  }
  async all(limit = 1000) {
    return [...this.events.values()].slice(-limit)
  }
}

export class TraceLog {
  constructor(
    private readonly store: TraceStore = new MemoryTraceStore(),
    private readonly clock: Clock = systemClock,
    private readonly ids: IdGenerator = randomIdGenerator,
  ) {}

  newContext(): TraceContext {
    return { traceId: this.ids('trc'), correlationId: this.ids('cor') }
  }

  async record(
    ctx: TraceContext,
    e: Pick<TraceEvent, 'eventType' | 'producer' | 'workspaceRef'> & Partial<Pick<TraceEvent, 'subjectRefs' | 'summary' | 'payload'>>,
  ): Promise<{ event: TraceEvent; next: TraceContext }> {
    if (ctx.causationId && !(await this.store.get(ctx.causationId))) {
      // Fail closed on a dangling causation: a chain that cannot be walked back is worse than none.
      throw new Error(`causationId ${ctx.causationId} is not a recorded event`)
    }
    const event = TraceEventSchema.parse({
      schemaVersion: SCHEMA_VERSION,
      eventId: this.ids('evt'),
      occurredAt: this.clock().toISOString(),
      traceId: ctx.traceId,
      correlationId: ctx.correlationId,
      causationId: ctx.causationId,
      ...e,
    })
    await this.store.append(event)
    return { event, next: { ...ctx, causationId: event.eventId } }
  }

  all(): Promise<TraceEvent[]> {
    return this.store.all()
  }

  byTrace(traceId: string): Promise<TraceEvent[]> {
    return this.store.byTrace(traceId)
  }

  /** Walks causationId back to the root: the answer to "why did this happen?". */
  async explain(eventId: string): Promise<TraceEvent[]> {
    const chain: TraceEvent[] = []
    const seen = new Set<string>()
    let cur = await this.store.get(eventId)
    while (cur && !seen.has(cur.eventId)) {
      seen.add(cur.eventId)
      chain.unshift(cur)
      cur = cur.causationId ? await this.store.get(cur.causationId) : undefined
    }
    return chain
  }
}
