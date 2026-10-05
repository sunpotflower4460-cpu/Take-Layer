import { createHash } from 'node:crypto'
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterAll, describe, expect, it } from 'vitest'
import {
  HttpRunnerTransport, LocalAssetResolver, preflightResolverCalibration, resolverCalibrationHandler, ResolverCalibrationArtifactSchema, MacJobQueue, MacRunner, RenderedMediaArtifactV1Schema, Workspace, buildRenderEnqueue, computePlanHash, createApp, defaultExec, preflightRenderEditPlan, renderEditPlanHandler, validateJobResults,
} from './shim.js'
import { fixedClock } from './helpers.js'

/**
 * REAL end-to-end on a Mac: Artist OS queue → Mac Runner → Take-Layer headless renderer (AVFoundation) → MP4 →
 * RenderedMediaArtifactV1 → server-side validation → COMPLETED. No fake renderer anywhere in this file.
 *
 * Runs ONLY on darwin with TAKE_LAYER_REPO pointing at a Take-Layer checkout; otherwise skipped (it cannot run on
 * Linux). Where it ran is recorded in docs/audit/TAKE_LAYER_MAC_PROOF.md — a GitHub-hosted macOS runner is
 * "CI_MACOS", NOT the user's own Mac.
 */
const REPO = process.env.TAKE_LAYER_REPO
const enabled = process.platform === 'darwin' && Boolean(REPO)
const NOW = '2026-10-05T12:00:00.000Z'
const sha = (b: Buffer) => createHash('sha256').update(b).digest('hex')

describe.skipIf(!enabled)('REAL Mac render e2e (Take-Layer headless renderer)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'aos-e2e-'))
  afterAll(() => rmSync(dir, { recursive: true, force: true }))
  const renderBin = join(dir, 'take-layer-render')

  it('preflight really builds the renderer and passes its own render self-test on THIS machine', async () => {
    expect(await preflightRenderEditPlan({ platform: process.platform, repoDir: REPO!, exec: defaultExec, renderBin })).toEqual({ ok: true })
  }, 40 * 60_000)

  it('drives a real job to COMPLETED, validates the artifact, keeps paths local, dedupes, rejects tampering, and reconciles a lost completion', async () => {
    const fx = join(dir, 'fx.json')
    expect((await defaultExec(renderBin, ['make-fixtures', '--workdir', join(dir, 'media'), '--result', fx], { timeoutMs: 5 * 60_000 })).code).toBe(0)
    const f = JSON.parse(readFileSync(fx, 'utf8')) as { videoPath: string; wavPath: string; videoSha256: string; wavSha256: string }
    const resolver = new LocalAssetResolver({ 'asset-video': f.videoPath, 'asset-wav': f.wavPath })
    const clk = fixedClock()
    const ws = new Workspace({ workspaceRef: 'w', queue: new MacJobQueue(undefined, { clock: clk.clock, runnerTtlMs: 600_000 }), clock: clk.clock })
    const app = createApp(ws, { operatorToken: 'op', runnerToken: 'rn', specialistConfig: {}, environment: 'development', macJobsRequested: true })
    const fetchImpl = (async (url: string, init: RequestInit) => {
      const r = await app({ method: init.method ?? 'GET', path: new URL(String(url)).pathname, headers: Object.fromEntries(Object.entries((init.headers ?? {}) as Record<string, string>)), body: init.body ? JSON.parse(String(init.body)) : undefined })
      return new Response(JSON.stringify(r.body), { status: r.status })
    }) as typeof fetch
    const outputDir = join(dir, 'renders')
    const handler = renderEditPlanHandler({ platform: process.platform, renderBin, exec: defaultExec, outputDir, registerOutput: (id, p) => resolver.register(id, p), timeoutMs: 20 * 60_000 })
    const runner = new MacRunner({ runnerId: 'mac1', architecture: process.arch, transport: new HttpRunnerTransport({ baseUrl: 'https://aos.test', token: 'rn', fetchImpl }), resolver, handlers: [handler] })
    await runner.beat()

    const ref = (kind: 'raw_video' | 'master_wav', id: string, hash: string) => ({ schemaVersion: 1 as const, assetRef: `ref-${id}`, ownerSystem: 'take-layer' as const, kind, locationType: 'runner-local' as const, runnerId: 'mac1', locationId: id, contentHash: `sha256:${hash}`, derivedFrom: [], createdAt: NOW })
    const timeline = { songStartRawSec: 1, songStartAudioSec: 0, offsetMs: 0 }
    const sources = { video: { durationSec: 8, width: 640, height: 360 }, masterAudio: { durationSec: 10, sampleRate: 48000, channelCount: 1 } }
    const mk = (edit: Record<string, unknown>, version = 1, video = ref('raw_video', 'asset-video', f.videoSha256)) => {
      const b = buildRenderEnqueue({ workspaceRef: 'w', plan: { planId: 'plan-e2e', planVersion: version, planHash: computePlanHash(edit as never, timeline) }, edit, timeline, sources, video, masterAudio: ref('master_wav', 'asset-wav', f.wavSha256) })
      if (!b.ok) throw new Error(`${b.code}: ${b.detail}`)
      return b.input
    }
    const edit = { rangeStartProjectSec: 0, rangeEndProjectSec: 4, titleText: 'E2E', crop: { zoom: 1.5, focusX: 0.5, focusY: 0.5 }, lyricCues: [{ startProjectSec: 0.5, endProjectSec: 2.5, text: 'テスト' }] }

    // 1) the happy path through the real HTTP runner API
    const first = await ws.queue.enqueue(mk(edit))
    if (!first.ok) throw new Error(first.detail)
    expect(await runner.drain()).toEqual(['completed'])
    const done = (await ws.queue.get(first.job.jobId))!
    expect(done.status).toBe('COMPLETED')
    const art = RenderedMediaArtifactV1Schema.parse(done.resultArtifacts[0])
    expect(validateJobResults('RENDER_EDIT_PLAN', done.resultArtifacts)).toEqual({ ok: true })
    expect(art.payload).toMatchObject({ width: 1080, height: 1920, audioSource: 'master_wav', validation: { passed: true } })
    expect(Math.abs(art.payload.durationSec - 4)).toBeLessThan(0.2)
    const out = resolver.resolveAssetId(art.payload.outputAssetRef.locationId)!
    expect(existsSync(out)).toBe(true)
    expect(`sha256:${sha(readFileSync(out))}`).toBe(art.payload.contentHash)
    // paths never persisted / transmitted
    const wire = JSON.stringify(await ws.queue.list()) + JSON.stringify(done)
    expect(wire).not.toContain(dir)
    expect(wire).not.toContain('fixture-video')

    // 2) same semantic request again: deduplicated, no second render
    expect(await ws.queue.enqueue(mk(edit, 2))).toMatchObject({ ok: true, deduplicated: true })

    // 3) tampered source bytes are refused by the Mac before rendering
    const tampered = join(dir, 'tampered.mp4')
    copyFileSync(f.videoPath, tampered)
    writeFileSync(tampered, Buffer.concat([readFileSync(tampered), Buffer.from('x')]))
    resolver.register('asset-video-tampered', tampered)
    const bad = await ws.queue.enqueue(mk({ ...edit, titleText: 'tamper' }, 3, ref('raw_video', 'asset-video-tampered', f.videoSha256)))
    if (!bad.ok) throw new Error(bad.detail)
    expect(await runner.drain()).toEqual(['failed'])
    expect((await ws.queue.get(bad.job.jobId))?.error?.code).toBe('ASSET_HASH_MISMATCH')

    // 4) an invalid plan (range beyond the real video) is refused by Take-Layer's own TimelineMapper
    const beyond = { ...edit, titleText: 'beyond', rangeEndProjectSec: 30 }
    const inv = await ws.queue.enqueue(mk(beyond, 4))
    if (!inv.ok) throw new Error(inv.detail)
    expect(await runner.drain()).toEqual(['failed'])
    expect((await ws.queue.get(inv.job.jobId))?.error?.code).toBe('INVALID_REQUEST')

    // 5) the Runner "dies" after a REAL render but before reporting: lease expires → BLOCKED → reconcile finds the real output
    const lost = await ws.queue.enqueue(mk({ ...edit, titleText: 'lost completion' }, 5))
    if (!lost.ok) throw new Error(lost.detail)
    const claimed = (await ws.queue.claim('mac1'))!
    await handler.run({ job: claimed, runnerId: 'mac1', resolveAsset: resolver.resolve, progress: async () => undefined })
    clk.advance(31 * 60_000)
    await ws.queue.reclaimExpired()
    expect(await ws.queue.get(lost.job.jobId)).toMatchObject({ status: 'BLOCKED', blockedReason: 'LOCAL_SIDE_EFFECT_UNKNOWN' })
    await ws.queue.requestReconcile(lost.job.jobId)
    await runner.beat()
    expect(await runner.reconcileTick()).toBe('reported')
    const rec = (await ws.queue.get(lost.job.jobId))!
    expect(rec).toMatchObject({ status: 'COMPLETED', reconcile: { outcome: 'completed' } })
    expect(validateJobResults('RENDER_EDIT_PLAN', rec.resultArtifacts)).toEqual({ ok: true })
  }, 40 * 60_000)
})

/** Mono PCM16 WAV of a note sequence with a given number of harmonics (a stand-in "arrangement"). */
function synthWav(notes: number[], opts: { noteSec: number; harmonics: number; rate?: number }): Buffer {
  const rate = opts.rate ?? 16_000
  const per = Math.floor(opts.noteSec * rate)
  const data = Buffer.alloc(notes.length * per * 2)
  notes.forEach((f, n) => {
    for (let i = 0; i < per; i++) {
      let v = 0
      for (let h = 1; h <= opts.harmonics; h++) v += Math.sin((2 * Math.PI * f * h * i) / rate) / h
      const env = Math.min(1, i / 400, (per - i) / 400)
      data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v * 0.3 * env)) * 32767), (n * per + i) * 2)
    }
  })
  const head = Buffer.alloc(44)
  head.write('RIFF', 0); head.writeUInt32LE(36 + data.length, 4); head.write('WAVEfmt ', 8); head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(1, 22)
  head.writeUInt32LE(rate, 24); head.writeUInt32LE(rate * 2, 28); head.writeUInt16LE(2, 32); head.writeUInt16LE(16, 34); head.write('data', 36); head.writeUInt32LE(data.length, 40)
  return Buffer.concat([head, data])
}

/**
 * REAL RESOLVER_CALIBRATION on a Mac: Take-Layer's own CLI (`tools/run-resolver-calibration.sh`, compiled by xcrun swiftc),
 * launched by the Runner handler. The corpus is SYNTHETIC (generated here): this proves the plumbing — process launch,
 * exit code, timeout wiring, report parsing, artifact validation, no path persistence, COMPLETED — NOT resolver quality.
 */
describe.skipIf(!enabled)('REAL Mac RESOLVER_CALIBRATION (Take-Layer CLI)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'aos-cal-e2e-'))
  afterAll(() => rmSync(dir, { recursive: true, force: true }))

  it('preflight really compiles and runs the CLI (--help) on this machine', async () => {
    expect(await preflightResolverCalibration({ platform: process.platform, repoDir: REPO!, exec: defaultExec })).toEqual({ ok: true })
  }, 30 * 60_000)

  it('one real calibration run through the Runner → COMPLETED with a valid summary artifact and no private paths stored', async () => {
    const corpus = join(dir, 'private-corpus-folder')
    mkdirSync(join(corpus, 'songs'), { recursive: true })
    const A = [262, 330, 392, 523, 392, 330, 262, 330, 392, 523]
    const B = [370, 466, 587, 740, 587, 466, 370, 466, 587, 740]
    writeFileSync(join(corpus, 'songs', 'a-studio.wav'), synthWav(A, { noteSec: 2, harmonics: 4 }))
    writeFileSync(join(corpus, 'songs', 'a-acoustic.wav'), synthWav(A, { noteSec: 2, harmonics: 2 }))
    writeFileSync(join(corpus, 'songs', 'b-studio.wav'), synthWav(B, { noteSec: 2, harmonics: 4 }))
    const manifest = join(dir, 'private-manifest-name.json')
    writeFileSync(manifest, JSON.stringify({ schemaVersion: 1, name: 'SYNTHETIC-PLUMBING-CHECK', cases: [
      { name: 'a acoustic vs studio', relationship: 'sameSongDifferentArrangement', queryPath: 'songs/a-acoustic.wav', referencePath: 'songs/a-studio.wav' },
      { name: 'b vs a', relationship: 'differentSong', queryPath: 'songs/b-studio.wav', referencePath: 'songs/a-studio.wav' },
    ] }))
    const resolver = new LocalAssetResolver({ 'manifest-1': manifest, 'corpus-root': corpus })
    const clk = fixedClock()
    const ws = new Workspace({ workspaceRef: 'w', queue: new MacJobQueue(undefined, { clock: clk.clock }), clock: clk.clock })
    const app = createApp(ws, { operatorToken: 'op', runnerToken: 'rn', specialistConfig: {}, environment: 'development', macJobsRequested: true })
    const fetchImpl = (async (url: string, init: RequestInit) => {
      const r = await app({ method: init.method ?? 'GET', path: new URL(String(url)).pathname, headers: Object.fromEntries(Object.entries((init.headers ?? {}) as Record<string, string>)), body: init.body ? JSON.parse(String(init.body)) : undefined })
      return new Response(JSON.stringify(r.body), { status: r.status })
    }) as typeof fetch
    const handler = resolverCalibrationHandler({ platform: process.platform, repoDir: REPO!, exec: defaultExec, resolveDir: (id) => resolver.resolveAssetId(id), timeoutMs: 30 * 60_000 })
    const runner = new MacRunner({ runnerId: 'mac1', architecture: process.arch, transport: new HttpRunnerTransport({ baseUrl: 'https://aos.test', token: 'rn', fetchImpl }), resolver, handlers: [handler] })
    await runner.beat()
    const q = await ws.queue.enqueue({ jobType: 'RESOLVER_CALIBRATION', workspaceRef: 'w', parameters: { corpusRootAssetId: 'corpus-root' }, inputAssetRefs: [{ schemaVersion: 1, assetRef: 'm1', ownerSystem: 'take-layer', kind: 'other', locationType: 'runner-local', runnerId: 'mac1', locationId: 'manifest-1', derivedFrom: [], createdAt: NOW }] })
    if (!q.ok) throw new Error(q.detail)
    expect(await runner.drain()).toEqual(['completed'])
    const job = (await ws.queue.get(q.job.jobId))!
    expect(job.status).toBe('COMPLETED')
    expect(ResolverCalibrationArtifactSchema.safeParse(job.resultArtifacts[0]).success).toBe(true)
    expect(validateJobResults('RESOLVER_CALIBRATION', job.resultArtifacts)).toEqual({ ok: true })
    expect(job.resultArtifacts[0]!.payload).toMatchObject({ totalCases: 2 })
    const wire = JSON.stringify(await ws.queue.list())
    for (const secret of ['private-corpus-folder', 'private-manifest-name', 'SYNTHETIC-PLUMBING-CHECK', 'a-studio', dir]) expect(wire).not.toContain(secret)
  }, 40 * 60_000)
})
