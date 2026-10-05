import { arch, homedir } from 'node:os'
import { join } from 'node:path'
import { HttpRunnerTransport, LocalAssetResolver, MacRunner } from './runner.js'
import { REGISTERED_HANDLERS } from './handlers/index.js'
import { preflightRenderEditPlan, renderEditPlanHandler } from './handlers/render-edit-plan.js'
import { defaultExec, preflightResolverCalibration, resolverCalibrationHandler } from './handlers/resolver-calibration.js'

/**
 * Artist Mac Runner (pull-based). Outbound HTTPS only.
 *   ARTIST_OS_URL            base URL of Artist OS
 *   ARTIST_OS_RUNNER_TOKEN   the Runner credential (separate from the operator token)
 *   ARTIST_OS_RUNNER_ID      default: hostname-like "runner-1"
 *   ARTIST_OS_RUNNER_ASSETS  JSON file {"<runner-local asset id>": "/absolute/path/to/file.wav"} — stays on this machine
 * Job handlers: AUDIO_ANALYSIS always; RESOLVER_CALIBRATION / RENDER_EDIT_PLAN only when TAKE_LAYER_REPO is set AND their
 * start-up preflight really works on this machine. Everything else is unsupported and not advertised.
 *   TAKE_LAYER_REPO / TAKE_LAYER_RENDER_BIN / ARTIST_OS_RENDER_OUTPUT_DIR (default ~/ArtistOS/renders)
 */
const env = process.env
const url = env.ARTIST_OS_URL
const token = env.ARTIST_OS_RUNNER_TOKEN
if (!url || !token) {
  console.error('ARTIST_OS_URL and ARTIST_OS_RUNNER_TOKEN are required.')
  process.exit(2)
}
const resolver = env.ARTIST_OS_RUNNER_ASSETS ? LocalAssetResolver.fromFile(env.ARTIST_OS_RUNNER_ASSETS) : new LocalAssetResolver({})
const handlers = [...REGISTERED_HANDLERS]
// Take-Layer integration: advertised ONLY if the CLI really runs on this machine (the preflight compiles and runs it).
if (env.TAKE_LAYER_REPO) {
  const d = { platform: process.platform, repoDir: env.TAKE_LAYER_REPO, exec: defaultExec, resolveDir: (id: string) => resolver.resolveAssetId(id) }
  const pre = await preflightResolverCalibration(d)
  if (pre.ok) handlers.push(resolverCalibrationHandler(d))
  console.log(pre.ok ? 'RESOLVER_CALIBRATION: enabled' : `RESOLVER_CALIBRATION: not advertised (${pre.reason})`)
}
// RENDER_EDIT_PLAN: advertised ONLY after a REAL render (synthetic media → MP4 → quality validation) succeeds on this machine.
if (env.TAKE_LAYER_REPO) {
  const renderBin = env.TAKE_LAYER_RENDER_BIN ?? join(env.TMPDIR ?? '/tmp', 'TakeLayerRender', 'take-layer-render')
  const pre = await preflightRenderEditPlan({ platform: process.platform, repoDir: env.TAKE_LAYER_REPO, exec: defaultExec, renderBin })
  if (pre.ok) {
    handlers.push(renderEditPlanHandler({ platform: process.platform, renderBin, exec: defaultExec, outputDir: env.ARTIST_OS_RENDER_OUTPUT_DIR ?? join(homedir(), 'ArtistOS', 'renders'), registerOutput: (id, path) => resolver.register(id, path) }))
  }
  console.log(pre.ok ? 'RENDER_EDIT_PLAN: enabled (self-test render passed on this machine)' : `RENDER_EDIT_PLAN: not advertised (${pre.reason})`)
}
const runner = new MacRunner({
  runnerId: env.ARTIST_OS_RUNNER_ID ?? 'runner-1',
  architecture: arch(),
  transport: new HttpRunnerTransport({ baseUrl: url, token }),
  resolver,
  handlers,
  version: '0.1.0',
})

let stopping = false
for (const sig of ['SIGINT', 'SIGTERM'] as const) process.on(sig, () => void (stopping = true))
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

let lastBeat = 0
while (!stopping) {
  try {
    if (Date.now() - lastBeat > 30_000) {
      await runner.beat('idle')
      lastBeat = Date.now()
    }
    // Operator-requested reconciliation of BLOCKED jobs this Mac used to hold comes first: it is read-only and cheap.
    if ((await runner.reconcileTick()) === 'reported') console.log('reconcile reported')
    const r = await runner.tick()
    if (r !== 'idle') console.log(`job ${r}`)
    if (r === 'idle') await sleep(5_000)
  } catch (e) {
    // Offline or server unreachable is NORMAL: queued jobs wait. Back off and try again.
    console.error('runner loop:', e instanceof Error ? e.message : 'error')
    await sleep(15_000)
  }
}
