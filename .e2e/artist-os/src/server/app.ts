import { timingSafeEqual } from 'node:crypto'
import { z } from 'zod'
import { type ClientConfigEntry, buildClients, clientConfigFromEnv } from '../clients/specialists.js'
import type { SpecialistClient } from '../clients/base.js'
import { type SystemId, SystemIdSchema, SourceRefSchema } from '../core/common.js'
import { AssetRefSchema } from '../core/asset.js'
import { EquipmentRegistry } from '../equipment/registry.js'
import { CapabilityRouter } from '../equipment/router.js'
import { PolicyGateway, authLayer, billingLayer, providerLayer, DEFAULT_PROVIDER_RULES } from '../policy/gateway.js'
import { buildAttentionQueue, decideAttention } from '../projection/attention.js'
import { buildReleaseDashboard } from '../projection/release-dashboard.js'
import { buildToday } from '../projection/today.js'
import { ServiceRegistry, buildServiceDescriptors } from '../registry/services.js'
import { aggregateHealth } from '../registry/health.js'
import { JOB_TYPES, RECONCILE_OUTCOMES } from '../runner/job.js'
import type { Workspace } from '../app/workspace.js'
import { renderHomePage } from './home-page.js'
import { validateJobResults } from '../runner/results.js'
import type { ExecutionOwner } from '../ledger/ownership.js'
import { type ActionKey, ActionKeyPartsSchema } from '../ledger/action-key.js'
import type { StoreInfo } from '../ledger/storage.js'
import { type WriteCoordination, evaluateWriteCoordination, type DeployEnvironment } from '../ledger/store-policy.js'

export interface AppConfig {
  operatorToken?: string
  runnerToken?: string
  /** Whether a service has a usable credential, for the policy `auth` layer. */
  specialistConfig: Partial<Record<SystemId, ClientConfigEntry>>
  fetchImpl?: typeof fetch
  /**
   * Credentials by which specialists identify THEMSELVES to the Action Ledger. The owner is derived from
   * the token that authenticated the call, never from the request body, so one system cannot reserve as another.
   * SNS-AI deliberately has no ledger credential: it never executes inbound replies.
   */
  ledgerTokens?: Partial<Record<ExecutionOwner, string>>
  environment?: DeployEnvironment
  /** ARTIST_OS_WRITE_COORDINATION=enabled */
  writeCoordinationRequested?: boolean
  /** ARTIST_OS_MAC_JOBS=enabled */
  macJobsRequested?: boolean
  /** What backs Mac jobs (the JSON state file today; a durable multi-process store is a later phase). */
  macJobsStore?: StoreInfo
}

export interface HttpRequest {
  method: string
  path: string
  headers: Record<string, string | undefined>
  body?: unknown
  query?: Record<string, string | undefined>
}
export interface HttpResponse {
  status: number
  body: unknown
  contentType?: string
}

const eq = (provided: string | undefined, expected: string) => {
  const a = Buffer.from(provided ?? '')
  const b = Buffer.from(expected)
  return a.length === b.length && timingSafeEqual(a, b)
}
const bearer = (h: HttpRequest['headers']) => (h.authorization?.startsWith('Bearer ') ? h.authorization.slice(7) : undefined)

const json = (status: number, body: unknown): HttpResponse => ({ status, body })
const notFound = json(404, { error: 'not_found' })

/**
 * Artist OS HTTP surface as a pure request→response function (transport-independent, easy to test).
 *
 *  - Operator API (human/AI manager): `ARTIST_OS_OPERATOR_TOKEN`
 *  - Runner API (Mac, pull-based, HTTPS): `ARTIST_OS_RUNNER_TOKEN` — separate credential, runner endpoints only
 *  Either token unset ⇒ that API answers 503 (fail closed). No endpoint executes commands.
 */
export function createApp(ws: Workspace, config: AppConfig) {
  const equipment = EquipmentRegistry.withDefaultCatalog()
  const registry = new ServiceRegistry(
    buildServiceDescriptors(Object.fromEntries(Object.entries(config.specialistConfig).map(([k, v]) => [k, { baseUrl: v?.baseUrl }]))),
  )
  const clients: Map<SystemId, SpecialistClient> = buildClients(config.specialistConfig, { fetchImpl: config.fetchImpl })
  const policy = new PolicyGateway([
    providerLayer(DEFAULT_PROVIDER_RULES),
    authLayer({ isAuthenticated: (req) => !req.system || Boolean(config.specialistConfig[req.system as SystemId]?.token) }),
    billingLayer(),
  ])
  const router = new CapabilityRouter(equipment)
  const clock = () => new Date()
  const environment = config.environment ?? 'production'
  const coordination: WriteCoordination = evaluateWriteCoordination({ environment, requested: config.writeCoordinationRequested ?? false, store: ws.ledger.storage.info })
  const macJobs: WriteCoordination = evaluateWriteCoordination({
    environment,
    requested: config.macJobsRequested ?? false,
    store: config.macJobsStore ?? ws.queue.info,
    switchName: 'ARTIST_OS_MAC_JOBS',
    subject: 'Mac jobs wait; the Runner API answers 503',
  })

  return async function handle(req: HttpRequest): Promise<HttpResponse> {
    const path = req.path.replace(/\/+$/, '') || '/'
    if (req.method === 'GET' && path === '/healthz') {
      return json(200, { ok: true, service: 'artist-os', environment, writeCoordination: { state: coordination.state, reason: coordination.reason }, macJobs: { state: macJobs.state, reason: macJobs.reason }, ledgerStore: ws.ledger.storage.info.kind })
    }

    // ---- Action Ledger (cross-system external-write coordination) ----
    if (path.startsWith('/api/ledger')) return ledgerRoutes(ws, req, path, config, coordination)

    // ---- Runner API ----
    if (path.startsWith('/api/runner/')) {
      if (macJobs.state !== 'enabled') return json(503, { error: 'MAC_JOBS_UNAVAILABLE', state: macJobs.state, reason: macJobs.state === 'refused' ? macJobs.detail : macJobs.reason })
      if (!config.runnerToken) return json(503, { error: 'runner API not configured' })
      if (!eq(bearer(req.headers), config.runnerToken)) return json(401, { error: 'unauthorized' })
      return await runnerRoutes(ws, req, path)
    }

    // ---- Operator API ----
    if (!config.operatorToken) return json(503, { error: 'operator API not configured' })
    // The home page itself carries no data; it asks for the token client-side.
    if (req.method === 'GET' && path === '/') return { status: 200, body: renderHomePage(), contentType: 'text/html; charset=utf-8' }
    if (!eq(bearer(req.headers), config.operatorToken)) return json(401, { error: 'unauthorized' })

    try {
      if (req.method === 'GET' && path === '/api/home') {
        const today = await buildToday({ clients, queue: ws.queue, equipment, clock, ledger: ws.ledger })
        return json(200, {
          goal: (await ws.currentGoal()) ?? null,
          releases: (await ws.releases()).filter((r) => r.status !== 'archived'),
          attentionCount: today.attention.length,
          runners: await ws.queue.runnerStates(),
          blockedJobs: await blockedJobsView(ws),
          services: registry.list().map((s) => ({ serviceId: s.serviceId, status: s.status, reason: s.degradedReason })),
          unreadableSources: today.unreadableSources,
          writeCoordination: { state: coordination.state, reason: coordination.reason },
          replyOwnership: today.replyOwnership,
        })
      }
      if (req.method === 'GET' && path === '/api/today') return json(200, await buildToday({ clients, queue: ws.queue, equipment, clock, ledger: ws.ledger }))
      if (req.method === 'GET' && path === '/api/health') return json(200, await aggregateHealth(registry, clients, clock))
      if (req.method === 'GET' && path === '/api/equipment') return json(200, equipment.list())
      if (req.method === 'GET' && path.startsWith('/api/route/')) return json(200, router.route(decodeURIComponent(path.slice('/api/route/'.length))))
      if (req.method === 'GET' && path === '/api/runners') return json(200, { runners: await ws.queue.runnerStates(), jobs: await ws.queue.list() })

      if (path === '/api/goals') {
        if (req.method === 'GET') return json(200, await ws.goals())
        if (req.method === 'POST') return json(201, await ws.createGoal(req.body as never))
      }
      if (path === '/api/releases') {
        if (req.method === 'GET') return json(200, await ws.releases())
        if (req.method === 'POST') return json(201, await ws.createRelease(req.body as never))
      }
      const rel = path.match(/^\/api\/releases\/([^/]+)(?:\/(dashboard|status|links|media-jobs))?$/)
      if (rel) {
        const release = await ws.release(rel[1]!)
        if (!release) return notFound
        if (req.method === 'GET' && rel[2] === 'dashboard') {
          const today = await buildToday({ clients, queue: ws.queue, equipment, clock, ledger: ws.ledger })
          return json(200, buildReleaseDashboard(release, await ws.identityGraph(), { attention: today.attention, activity: [] }))
        }
        if (req.method === 'POST' && rel[2] === 'status') return json(200, await ws.transitionRelease(release.releaseId, z.object({ to: z.enum(['planning', 'in_production', 'scheduled', 'released', 'archived']) }).parse(req.body).to))
        if (req.method === 'POST' && rel[2] === 'links') {
          const b = z.object({ system: SystemIdSchema, entityType: z.string(), entityId: z.string(), evidence: z.enum(['human_confirmed', 'shared_strong_identifier', 'source_attested', 'title_match', 'handle_match', 'display_name_match']), confidence: z.number().min(0).max(1), note: z.string().optional() }).parse(req.body)
          return json(201, await ws.proposeReleaseLink(release.releaseId, { system: b.system, entityType: b.entityType, entityId: b.entityId }, b.evidence, b.confidence, b.note))
        }
        if (req.method === 'POST' && rel[2] === 'media-jobs') {
          // Release → media request → Mac job, on ONE trace (so "why does this artifact exist?" is answerable).
          const b = z.object({ jobType: z.enum(JOB_TYPES), parameters: z.record(z.string(), z.json()).optional(), inputAssetRefs: z.array(AssetRefSchema).max(50).optional(), idempotencyKey: z.string().optional() }).parse(req.body)
          const out = await ws.requestMediaJob(release.releaseId, b.jobType, b)
          return json(out.result.ok ? 201 : 409, { ...out.result, traceId: out.trace.traceId })
        }
        if (req.method === 'GET' && !rel[2]) return json(200, release)
      }
      const link = path.match(/^\/api\/links\/([^/]+)\/(confirm|reject|revoke)$/)
      if (link && req.method === 'POST') {
        // Only an authenticated operator reaches here, so this is a human confirmation by definition.
        const actor = { kind: 'human' as const, id: 'operator' }
        const id = link[1]!
        return json(200, await (link[2] === 'confirm' ? ws.confirmLink(id, actor) : link[2] === 'reject' ? ws.rejectLink(id) : ws.revokeLink(id)))
      }

      if (req.method === 'POST' && path === '/api/mac-jobs') {
        const b = z.object({ jobType: z.enum(JOB_TYPES), parameters: z.record(z.string(), z.json()).optional(), priority: z.number().int().optional(), idempotencyKey: z.string().optional(), inputAssetRefs: z.array(AssetRefSchema).max(50).optional(), subjectRefs: z.array(SourceRefSchema).max(20).optional() }).parse(req.body)
        const r = await ws.queue.enqueue({ ...b, workspaceRef: ws.workspaceRef })
        return json(r.ok ? 201 : 409, r)
      }
      const jobCancel = path.match(/^\/api\/mac-jobs\/([^/]+)\/cancel$/)
      const jobResolve = path.match(/^\/api\/mac-jobs\/([^/]+)\/resolve$/)
      if (jobResolve && req.method === 'POST') {
        // A BLOCKED job (lease expired where an automatic retry is unsafe) is released only by a human decision with evidence.
        const b = z.object({ action: z.enum(['requeue', 'fail']), evidence: z.string().max(500) }).parse(req.body)
        return json(200, await ws.queue.resolve(jobResolve[1]!, b))
      }
      const jobReconcile = path.match(/^\/api\/mac-jobs\/([^/]+)\/reconcile$/)
      if (jobReconcile && req.method === 'POST') {
        // "Request reconciliation": asks the Mac that held the job to look at what exists. Offline is a normal state (it waits).
        const job = await ws.queue.get(jobReconcile[1]!)
        if (!job) return notFound
        const updated = await ws.queue.requestReconcile(job.jobId)
        const runner = (await ws.queue.runnerStates()).find((r) => r.runnerId === updated.runnerId)
        return json(200, { job: updated, waitingForRunner: !runner?.online })
      }
      if (jobCancel && req.method === 'POST') return json(200, await ws.queue.cancel(jobCancel[1]!))

      const traceGet = path.match(/^\/api\/trace\/([^/]+)$/)
      if (req.method === 'GET' && traceGet) return json(200, { traceId: traceGet[1], events: await ws.trace.byTrace(traceGet[1]!) })
      const explain = path.match(/^\/api\/trace\/event\/([^/]+)\/explain$/)
      if (req.method === 'GET' && explain) return json(200, { chain: await ws.trace.explain(explain[1]!) })
      if (req.method === 'POST' && path === '/api/assets') return json(201, await ws.registerAsset(req.body as never))

      if (req.method === 'POST' && path === '/api/attention/decide') {
        const b = z.object({ sourceSystem: SystemIdSchema, sourceEntityType: z.string(), sourceEntityId: z.string(), decision: z.enum(['approve', 'reject']) }).parse(req.body)
        const today = await buildToday({ clients, queue: ws.queue, equipment, clock, ledger: ws.ledger })
        const item = buildAttentionQueue(today.attention).find((i) => i.sourceSystem === b.sourceSystem && i.sourceEntityType === b.sourceEntityType && i.sourceEntityId === b.sourceEntityId)
        // The item must be a LIVE item reported by the specialist right now: no stale or invented approvals.
        if (!item) return json(404, { error: 'attention item not found at source' })
        const ctx = ws.trace.newContext()
        return json(200, await decideAttention(item, b.decision, { clients, policy, trace: ws.trace, traceCtx: ctx, humanActorId: 'operator', workspaceRef: ws.workspaceRef }))
      }
    } catch (e) {
      if (e instanceof z.ZodError) return json(400, { error: 'invalid_request', detail: e.issues[0]?.message })
      // Domain rule violations (illegal transition, identity conflict, ...) are the caller's to fix.
      if (e instanceof Error) return json(409, { error: 'rejected', detail: e.message.slice(0, 300) })
      throw e
    }
    return notFound
  }
}

/**
 * BLOCKED Mac jobs for the operator: what is stuck, why, which Mac holds the answer, and whether that Mac is reachable.
 * Never a blind success/failure choice: the action is "ask the Mac" (reconcile), and an offline Mac simply means waiting.
 */
async function blockedJobsView(ws: Workspace) {
  const [jobs, runners] = await Promise.all([ws.queue.list({ status: 'BLOCKED' }), ws.queue.runnerStates()])
  return jobs.map((j) => {
    const runner = runners.find((r) => r.runnerId === j.runnerId)
    const online = Boolean(runner?.online)
    const canReconcile = j.blockedReason === 'LOCAL_SIDE_EFFECT_UNKNOWN'
    return {
      jobId: j.jobId,
      jobType: j.jobType,
      blockedReason: j.blockedReason,
      runnerId: j.runnerId,
      runnerOnline: online,
      reconcile: j.reconcile ?? null,
      canReconcile,
      // 'waiting_for_studio_mac' = reconcile requested but the Mac that must answer is offline.
      state: j.reconcile?.state === 'ambiguous' ? 'ambiguous_needs_human' : j.reconcile && !online ? 'waiting_for_studio_mac' : j.reconcile ? 'reconcile_requested' : 'blocked',
    }
  })
}

async function runnerRoutes(ws: Workspace, req: HttpRequest, path: string): Promise<HttpResponse> {
  try {
    if (req.method === 'POST' && path === '/api/runner/heartbeat') return json(200, await ws.queue.heartbeat(req.body))
    if (req.method === 'POST' && path === '/api/runner/claim') {
      const { runnerId } = z.object({ runnerId: z.string().min(1) }).parse(req.body)
      const job = await ws.queue.claim(runnerId)
      return json(200, { job: job ?? null })
    }
    if (req.method === 'POST' && path === '/api/runner/reconcile/claim') {
      const { runnerId } = z.object({ runnerId: z.string().min(1) }).parse(req.body)
      return json(200, { job: (await ws.queue.claimReconcile(runnerId)) ?? null })
    }
    const rec = path.match(/^\/api\/runner\/reconcile\/([^/]+)$/)
    if (req.method === 'POST' && rec) {
      const b = z.object({ runnerId: z.string().min(1), outcome: z.enum(RECONCILE_OUTCOMES), evidence: z.string().max(500), resultArtifacts: z.array(z.unknown()).optional() }).parse(req.body)
      const job = await ws.queue.get(rec[1]!)
      if (job && b.outcome === 'completed') {
        // A "completed" reconciliation is accepted only with the same artifact validation as a normal completion.
        const check = validateJobResults(job.jobType, b.resultArtifacts ?? [])
        if (!check.ok) return json(422, { error: check.code, message: check.message })
      }
      const updated = await ws.queue.completeReconcile(rec[1]!, b.runnerId, { outcome: b.outcome, evidence: b.evidence, resultArtifacts: b.resultArtifacts as never })
      if (updated.status === 'COMPLETED') await ws.recordJobOutcome(updated.jobId)
      return json(200, updated)
    }
    const upd = path.match(/^\/api\/runner\/jobs\/([^/]+)$/)
    if (req.method === 'POST' && upd) {
      const b = z.object({ runnerId: z.string(), attempt: z.number().int().optional(), status: z.enum(['PREPARING', 'RUNNING', 'VERIFYING', 'COMPLETED', 'FAILED', 'BLOCKED']).optional(), progress: z.number().min(0).max(1).optional(), currentStage: z.string().max(128).optional(), error: z.object({ code: z.string(), message: z.string(), retryable: z.boolean() }).optional(), resultArtifactRefs: z.array(z.any()).optional(), resultArtifacts: z.array(z.unknown()).optional() }).parse(req.body)
      const { runnerId, ...patch } = b
      if (patch.status === 'COMPLETED') {
        // A Runner is untrusted input: results are accepted only if they validate for this job type.
        const job = await ws.queue.get(upd[1]!)
        if (job) {
          const check = validateJobResults(job.jobType, patch.resultArtifacts ?? [])
          if (!check.ok) {
            await ws.queue.update(job.jobId, runnerId, { status: 'FAILED', error: { code: check.code, message: check.message, retryable: false } })
            await ws.recordJobOutcome(job.jobId)
            return json(422, { error: check.code, message: check.message })
          }
        }
      }
      const updated = await ws.queue.update(upd[1]!, runnerId, patch as never)
      if (updated.status === 'COMPLETED' || updated.status === 'FAILED') await ws.recordJobOutcome(updated.jobId)
      return json(200, updated)
    }
  } catch (e) {
    if (e instanceof z.ZodError) return json(400, { error: 'invalid_request', detail: e.issues[0]?.message })
    if (e instanceof Error) return json(409, { error: 'rejected', detail: e.message.slice(0, 300) })
  }
  return notFound
}

export { clientConfigFromEnv }


const timingEq = (provided: string | undefined, expected: string) => {
  const a = Buffer.from(provided ?? '')
  const b = Buffer.from(expected)
  return a.length === b.length && timingSafeEqual(a, b)
}

/** Identity of the caller from its credential: a specialist system, the operator, or nobody. */
function ledgerCaller(req: HttpRequest, config: AppConfig): { kind: 'system'; system: ExecutionOwner } | { kind: 'operator' } | undefined {
  const tok = bearer(req.headers)
  if (!tok) return undefined
  for (const [system, expected] of Object.entries(config.ledgerTokens ?? {}) as [ExecutionOwner, string | undefined][]) {
    if (expected && timingEq(tok, expected)) return { kind: 'system', system }
  }
  if (config.operatorToken && timingEq(tok, config.operatorToken)) return { kind: 'operator' }
  return undefined
}

function redact<T extends { reservationToken?: string }>(row: T): Omit<T, 'reservationToken'> {
  const rest: Record<string, unknown> = { ...row }
  delete rest.reservationToken
  return rest as Omit<T, 'reservationToken'>
}

async function ledgerRoutes(ws: Workspace, req: HttpRequest, path: string, config: AppConfig, coordination: WriteCoordination): Promise<HttpResponse> {
  const caller = ledgerCaller(req, config)
  if (!caller) return json(401, { error: 'unauthorized' })
  const keyOf = (b: unknown): ActionKey => {
    const o = z.object({ actionKey: z.string().optional() }).passthrough().parse(b)
    if (o.actionKey) {
      const [platform, operation, ...rest] = o.actionKey.split(':')
      return makeKey(ActionKeyPartsSchema.parse({ platform, operation, externalEventId: rest.join(':') }))
    }
    return makeKey(ActionKeyPartsSchema.parse(b))
  }
  try {
    // Reads
    if (req.method === 'GET' && path === '/api/ledger') {
      if (caller.kind !== 'operator') return json(403, { error: 'operator only' })
      const state = (req.query?.state as string | undefined) || undefined
      // Fencing tokens are credentials for begin/complete: never list them.
      return json(200, { rows: (await ws.ledger.list({ state: state as never, limit: 200 })).map(redact) })
    }
    // Every mutation (and per-key read) needs coordination to be genuinely enabled: otherwise specialists must fail closed.
    if (coordination.state !== 'enabled') {
      return json(503, { error: 'WRITE_COORDINATION_UNAVAILABLE', state: coordination.state, reason: coordination.state === 'refused' ? coordination.detail : coordination.reason })
    }
    if (req.method === 'POST' && path === '/api/ledger/reserve') {
      if (caller.kind !== 'system') return json(403, { error: 'only a specialist system can reserve' })
      const parts = ActionKeyPartsSchema.parse((req.body as Record<string, unknown>) ?? {})
      const r = await ws.ledger.reserve(caller.system, parts)
      // 200 for every well-formed answer: the body status is the contract. Only ACQUIRED permits a send.
      return json(200, { ...r, actionKey: makeKey(parts) })
    }
    if (req.method === 'POST' && (path === '/api/ledger/begin' || path === '/api/ledger/complete')) {
      if (caller.kind !== 'system') return json(403, { error: 'only a specialist system can drive its reservation' })
      const b = z.object({ reservationToken: z.string().min(1) }).passthrough().parse(req.body)
      const key = keyOf(req.body)
      if (path.endsWith('/begin')) return json(200, await ws.ledger.begin(caller.system, key, b.reservationToken))
      const o = z.discriminatedUnion('outcome', [
        z.object({ outcome: z.literal('succeeded'), outcomeRef: z.string().max(200).optional() }),
        z.object({ outcome: z.literal('failed_safe'), failureCode: z.string().max(100) }),
        z.object({ outcome: z.literal('unknown'), reason: z.string().max(200) }),
      ]).parse(req.body)
      return json(200, await ws.ledger.complete(caller.system, key, b.reservationToken, o))
    }
    if (req.method === 'POST' && path === '/api/ledger/reconcile') {
      const b = z.object({ resolution: z.enum(['sent', 'not_sent']), evidence: z.string().max(500), outcomeRef: z.string().max(200).optional() }).parse(req.body)
      const by = caller.kind === 'operator' ? 'operator' : caller.system
      const r = await ws.ledger.reconcile(by, keyOf(req.body), b)
      return json(200, r)
    }
    if (req.method === 'POST' && path === '/api/ledger/state') {
      const row = await ws.ledger.get(keyOf(req.body))
      return json(200, 'reservationToken' in row ? redact(row) : row)
    }
  } catch (e) {
    if (e instanceof z.ZodError) return json(400, { error: 'invalid_request', detail: e.issues[0]?.message })
    return json(500, { error: 'ledger_error' })
  }
  return notFound
}

import { makeActionKey as makeKey } from '../ledger/action-key.js'
