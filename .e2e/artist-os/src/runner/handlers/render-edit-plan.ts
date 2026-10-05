import { createHash } from 'node:crypto'
import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises'
import { createReadStream } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { z } from 'zod'
import { AssetRefSchema, type AssetRef } from '../../core/asset.js'
import { RENDER_PROFILE, RENDERED_MEDIA_ARTIFACT_VERSION, RenderEditPlanParametersSchema, RenderedMediaArtifactV1Schema, type RenderEditPlanParameters } from '../../artifacts/render.js'
import { renderRequestKey } from '../../artifacts/render.js'
import type { ArtifactEnvelope } from '../../artifacts/pipeline.js'
import { type ExecFn } from './resolver-calibration.js'
import { HandlerError, type HandlerContext, type JobHandler, type ReconcileReport } from './types.js'

/**
 * RENDER_EDIT_PLAN handler — drives Take-Layer's headless renderer (`take-layer-render`, built from the SAME Swift
 * sources as the iOS app, so TimelineMapper stays the one sync authority).
 *
 * It is a typed adapter, not a command runner: a fixed argument vector (`render --request <file> --result <file>`),
 * a request file the Runner writes itself from validated parameters + locally resolved paths, and strict validation
 * of what comes back. The Runner never trusts the renderer's word: it re-hashes the output and checks the commit marker.
 *
 * Privacy: local paths exist only in the private request file (deleted after the run). The output stays on the Mac;
 * only a runner-local asset id + hash + measurements leave in the RenderedMediaArtifactV1.
 */
export interface RenderDeps {
  platform: string
  /** Path of the built `take-layer-render` binary on this Mac. */
  renderBin: string
  exec: ExecFn
  /** Where rendered files live (Mac-local). */
  outputDir: string
  /** Registers the finished file under an opaque asset id (path stays on this Mac). */
  registerOutput(assetId: string, path: string): void
  now?: () => Date
  timeoutMs?: number
  /** A partial file untouched for this long belongs to a dead render. */
  abandonedPartialMs?: number
}

const SCRIPT = 'tools/build-render-cli.sh'
const hex = (h: string) => h.replace(/^sha256:/, '')

export async function sha256File(path: string): Promise<string> {
  const h = createHash('sha256')
  await new Promise<void>((resolve, reject) => {
    const s = createReadStream(path)
    s.on('data', (c) => h.update(c))
    s.on('end', () => resolve())
    s.on('error', reject)
  })
  return h.digest('hex')
}

const RenderCheckS = z.object({ name: z.string(), ok: z.boolean(), detail: z.string() })
/** The renderer's result JSON (it contains local paths; it is read on the Mac and never forwarded). */
export const RendererResultSchema = z.object({
  schemaVersion: z.literal(1),
  requestKey: z.string(),
  status: z.enum(['completed', 'failed']),
  errorCode: z.string().optional(),
  errorMessage: z.string().optional(),
  renderer: z.string().optional(),
  rendererVersion: z.string().optional(),
  outputPath: z.string().optional(),
  contentHash: z.string().regex(/^[0-9a-f]{64}$/).optional(),
  sizeBytes: z.number().optional(),
  durationSec: z.number().optional(),
  width: z.number().optional(),
  height: z.number().optional(),
  fps: z.number().optional(),
  audioSource: z.string().optional(),
  checks: z.array(RenderCheckS).default([]),
})
export type RendererResult = z.infer<typeof RendererResultSchema>

/** What the renderer commits NEXT TO the output after the atomic rename. The only proof a render completed. */
export const CommitMarkerSchema = z.object({
  schemaVersion: z.literal(1),
  requestKey: z.string(),
  contentHash: z.string().regex(/^[0-9a-f]{64}$/),
  sizeBytes: z.number(),
  durationSec: z.number(),
  width: z.number(),
  height: z.number(),
  fps: z.number(),
  renderer: z.string(),
  rendererVersion: z.string(),
  audioSource: z.string(),
  checks: z.array(RenderCheckS),
  committedAt: z.string(),
})
export type CommitMarker = z.infer<typeof CommitMarkerSchema>

export async function preflightRenderEditPlan(d: { platform: string; repoDir: string; exec: ExecFn; renderBin: string; workDir?: string }): Promise<{ ok: true } | { ok: false; reason: string }> {
  if (d.platform !== 'darwin') return { ok: false, reason: `needs macOS (AVFoundation); this runner is ${d.platform}` }
  if (!existsSync(join(d.repoDir, SCRIPT))) return { ok: false, reason: `TAKE_LAYER_REPO does not contain ${SCRIPT}` }
  const build = await d.exec('bash', [join(d.repoDir, SCRIPT), d.renderBin], { timeoutMs: 20 * 60_000, cwd: d.repoDir })
  if (build.code !== 0) return { ok: false, reason: 'the headless renderer did not compile on this machine' }
  const help = await d.exec(d.renderBin, ['--help'], { timeoutMs: 30_000 })
  if (help.code !== 0) return { ok: false, reason: 'the headless renderer did not start (--help exited non-zero)' }
  // Capability is earned by a REAL render on THIS machine: synthetic media → MP4 → the renderer's own quality validation.
  const work = await mkdtemp(join(d.workDir ?? tmpdir(), 'aos-render-selftest-'))
  try {
    const result = join(work, 'result.json')
    const r = await d.exec(d.renderBin, ['self-test', '--workdir', work, '--result', result], { timeoutMs: 10 * 60_000 })
    if (r.code !== 0) return { ok: false, reason: 'the render self-test failed (see the renderer; no capability is advertised)' }
    const parsed = RendererResultSchema.safeParse(JSON.parse(await readFile(result, 'utf8')))
    if (!parsed.success || parsed.data.status !== 'completed' || parsed.data.checks.length === 0 || parsed.data.checks.some((c) => !c.ok)) return { ok: false, reason: 'the render self-test did not pass quality validation' }
    return { ok: true }
  } catch {
    return { ok: false, reason: 'the render self-test produced no readable result' }
  } finally {
    await rm(work, { recursive: true, force: true })
  }
}

interface Resolved {
  params: RenderEditPlanParameters
  video: AssetRef
  audio: AssetRef
  requestKey: string
  outputPath: string
}

function outputPathFor(d: RenderDeps, jobId: string) {
  return join(d.outputDir, `${jobId}.mp4`)
}

function parse(ctx: HandlerContext, d: RenderDeps): Resolved {
  const params = RenderEditPlanParametersSchema.safeParse(ctx.job.parameters)
  if (!params.success) throw new HandlerError('INVALID_PARAMETERS', params.error.issues[0]?.message ?? 'invalid parameters')
  const refs = ctx.job.inputAssetRefs
  const video = refs.find((r) => r.kind === 'raw_video')
  const audio = refs.find((r) => r.kind === 'master_wav')
  if (refs.length !== 2 || !video || !audio) throw new HandlerError('INVALID_INPUT', 'RENDER_EDIT_PLAN takes exactly one raw_video and one master_wav')
  for (const r of [video, audio]) {
    if (r.locationType !== 'runner-local' || r.runnerId !== ctx.runnerId) throw new HandlerError('ASSET_NOT_ON_THIS_RUNNER', 'both sources must be runner-local assets of this runner')
    if (!r.contentHash) throw new HandlerError('ASSET_HASH_REQUIRED', 'sources need a contentHash')
  }
  const requestKey = ctx.job.idempotencyKey ?? renderRequestKey(params.data.plan.planHash, video.contentHash!, audio.contentHash!)
  return { params: params.data, video, audio, requestKey, outputPath: outputPathFor(d, ctx.job.jobId) }
}

function buildArtifact(ctx: HandlerContext, r: Resolved, m: CommitMarker, d: RenderDeps): ArtifactEnvelope {
  const assetId = `asset-${m.contentHash.slice(0, 24)}`
  const outputAssetRef: AssetRef = AssetRefSchema.parse({
    schemaVersion: 1,
    assetRef: `render-${ctx.job.jobId}`,
    ownerSystem: 'take-layer',
    kind: 'derived_video',
    locationType: 'runner-local',
    locationId: assetId,
    runnerId: ctx.runnerId,
    contentHash: `sha256:${m.contentHash}`,
    size: m.sizeBytes,
    mimeType: 'video/mp4',
    derivedFrom: [r.video.assetRef, r.audio.assetRef],
    generator: m.renderer,
    generatorVersion: m.rendererVersion,
    createdAt: m.committedAt,
  })
  d.registerOutput(assetId, r.outputPath)
  const artifact = RenderedMediaArtifactV1Schema.parse({
    schemaVersion: 1,
    artifactId: `art_${ctx.job.jobId}`,
    kind: 'RenderedMediaArtifact',
    producer: 'mac-runner',
    createdAt: m.committedAt,
    subjectRefs: ctx.job.subjectRefs,
    traceId: ctx.job.traceId,
    payloadVersion: RENDERED_MEDIA_ARTIFACT_VERSION,
    payload: {
      sourceAssetRefs: [
        { role: 'video', assetRef: r.video.assetRef, contentHash: r.video.contentHash },
        { role: 'master_wav', assetRef: r.audio.assetRef, contentHash: r.audio.contentHash },
      ],
      editingPlanRef: r.params.plan,
      outputAssetRef,
      contentHash: `sha256:${m.contentHash}`,
      sizeBytes: m.sizeBytes,
      durationSec: m.durationSec,
      width: m.width,
      height: m.height,
      fps: m.fps,
      renderer: m.renderer,
      rendererVersion: m.rendererVersion,
      profile: RENDER_PROFILE,
      audioSource: m.audioSource,
      validation: { checks: m.checks.map((c) => ({ name: c.name.slice(0, 64), ok: c.ok, detail: c.detail.slice(0, 200) })), passed: true },
      renderedAt: m.committedAt,
    },
  })
  return artifact
}

async function readMarker(outputPath: string): Promise<CommitMarker | undefined> {
  try {
    return CommitMarkerSchema.parse(JSON.parse(await readFile(`${outputPath}.commit.json`, 'utf8')))
  } catch {
    return undefined
  }
}

export function renderEditPlanHandler(d: RenderDeps): JobHandler {
  return {
    jobType: 'RENDER_EDIT_PLAN',

    async run(ctx) {
      const r = parse(ctx, d)
      const videoPath = ctx.resolveAsset(r.video)
      const audioPath = ctx.resolveAsset(r.audio)
      if (!videoPath || !audioPath) throw new HandlerError('ASSET_NOT_FOUND', 'this runner has no local file registered for a source asset', true)
      // The Mac verifies the BYTES it is about to render against the hash the request was made for.
      for (const [name, path, ref] of [['video', videoPath, r.video], ['master audio', audioPath, r.audio]] as const) {
        let actual: string
        try {
          actual = await sha256File(path)
        } catch {
          throw new HandlerError('ASSET_NOT_FOUND', `the ${name} file is not readable on this runner`, true)
        }
        if (`sha256:${actual}` !== ref.contentHash) throw new HandlerError('ASSET_HASH_MISMATCH', `the ${name} file on this Mac does not match the hash the render was requested for`)
      }

      await mkdir(d.outputDir, { recursive: true })
      const priv = await mkdtemp(join(tmpdir(), 'aos-render-'))
      try {
        const reqPath = join(priv, 'request.json')
        const resPath = join(priv, 'result.json')
        const request = {
          schemaVersion: 1,
          requestKey: r.requestKey,
          plan: r.params.plan,
          edit: r.params.edit,
          video: { runnerAssetId: r.video.locationId, localPath: videoPath, sha256: hex(r.video.contentHash!), ...r.params.sources.video },
          masterAudio: { runnerAssetId: r.audio.locationId, localPath: audioPath, sha256: hex(r.audio.contentHash!), hasAudio: true, ...r.params.sources.masterAudio },
          timeline: r.params.timeline,
          outputPath: r.outputPath,
        }
        await writeFile(reqPath, JSON.stringify(request), { mode: 0o600 })
        await ctx.progress(0.1, 'rendering')
        const exec = await d.exec(d.renderBin, ['render', '--request', reqPath, '--result', resPath], { timeoutMs: d.timeoutMs ?? 25 * 60_000 })
        let result: RendererResult | undefined
        try {
          result = RendererResultSchema.parse(JSON.parse(await readFile(resPath, 'utf8')))
        } catch {
          result = undefined
        }
        if (exec.code !== 0 || !result || result.status !== 'completed') {
          // Pre-render refusals (bad request, hash mismatch, quality failure) are deterministic: not retryable.
          throw new HandlerError(result?.errorCode?.slice(0, 64) ?? 'RENDER_FAILED', (result?.errorMessage ?? `the renderer exited with code ${exec.code}`).slice(0, 300), false)
        }
        // Do not trust the renderer's word: the commit marker and the bytes on disk decide.
        const marker = await readMarker(r.outputPath)
        let actualHash: string | undefined
        try {
          actualHash = await sha256File(r.outputPath)
        } catch {
          actualHash = undefined
        }
        if (!marker || !actualHash || marker.contentHash !== actualHash || marker.requestKey !== r.requestKey || result.contentHash !== actualHash) {
          throw new HandlerError('OUTPUT_UNVERIFIED', 'the renderer reported success but the output and its commit marker do not agree', false)
        }
        if (marker.checks.some((c) => !c.ok) || marker.audioSource !== 'master_wav') throw new HandlerError('RENDER_QUALITY_FAILED', 'the output did not pass render quality validation', false)
        return { artifacts: [buildArtifact(ctx, r, marker, d)] }
      } finally {
        await rm(priv, { recursive: true, force: true }) // the request file holds local paths
      }
    },

    async reconcile(ctx): Promise<ReconcileReport> {
      const r = parse(ctx, d)
      const now = (d.now ?? (() => new Date()))().getTime()
      const partial = r.outputPath.replace(/\.mp4$/, '') + '.partial.mp4'
      const marker = await readMarker(r.outputPath)
      const finalExists = existsSync(r.outputPath)
      if (marker && finalExists) {
        const actual = await sha256File(r.outputPath)
        if (marker.requestKey === r.requestKey && marker.contentHash === actual && marker.checks.length > 0 && marker.checks.every((c) => c.ok)) {
          return { outcome: 'completed', evidence: 'the output file exists, its commit marker matches this request, and the file hash equals the marker hash', artifacts: [buildArtifact(ctx, r, marker, d)] }
        }
        return { outcome: 'ambiguous', evidence: 'an output and a commit marker exist but they do not agree with each other or with this request' }
      }
      if (finalExists || marker) return { outcome: 'ambiguous', evidence: finalExists ? 'an output file exists without a valid commit marker' : 'a commit marker exists without the output file' }
      let partialStat
      try {
        partialStat = await stat(partial)
      } catch {
        partialStat = undefined
      }
      if (partialStat) {
        // A live render keeps writing its partial; one untouched for a while belongs to a render that died.
        if (now - partialStat.mtimeMs < (d.abandonedPartialMs ?? 120_000)) return { outcome: 'ambiguous', evidence: 'a partial file was modified very recently: a render may still be running' }
        await rm(partial, { force: true })
        return { outcome: 'not_completed', evidence: 'no output and no commit marker; an abandoned partial file was removed' }
      }
      return { outcome: 'not_completed', evidence: 'no output, no partial file and no commit marker exist for this job' }
    },
  }
}
