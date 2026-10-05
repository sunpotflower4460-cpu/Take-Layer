import { createHash } from 'node:crypto'
import { execFile } from 'node:child_process'
import { existsSync } from 'node:fs'
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { CALIBRATION_ARTIFACT_VERSION, ResolverCalibrationArtifactSchema, ResolverCalibrationParametersSchema, summarizeCalibrationReport } from '../../artifacts/resolver-calibration.js'
import { HandlerError, type JobHandler } from './types.js'

/**
 * RESOLVER_CALIBRATION — the first real Mac → Take-Layer integration.
 *
 * Runs Take-Layer's OWN headless CLI (`tools/run-resolver-calibration.sh`) with a FIXED argument vector built from
 * local, runner-resolved paths. It is not a general command runner: the only server-controlled input is the
 * optional list of confidence thresholds, validated as numbers 0..1. No shell string is ever built.
 *
 * It exists only where it works: `preflightResolverCalibration` actually runs the CLI's `--help` (which compiles it
 * with xcrun swiftc, exactly Take-Layer's own CI smoke step). If that fails (not macOS, no toolchain, no checkout)
 * the handler is NOT registered and the Runner does not advertise the capability.
 *
 * Privacy: the private corpus audio and the full report never leave the Mac; only a numeric summary is returned.
 */
export type ExecFn = (file: string, args: readonly string[], opts: { timeoutMs: number; cwd?: string }) => Promise<{ code: number }>

export const defaultExec: ExecFn = (file, args, opts) =>
  new Promise((resolve) => {
    // stdout/stderr are discarded: they can contain corpus paths/names and must never travel.
    execFile(file, [...args], { timeout: opts.timeoutMs, cwd: opts.cwd, maxBuffer: 1 << 20, windowsHide: true }, (err) => {
      const code = err ? (typeof (err as { code?: unknown }).code === 'number' ? ((err as { code: number }).code) : 1) : 0
      resolve({ code })
    })
  })

export interface CalibrationDeps {
  platform: string
  /** Take-Layer checkout on this Mac. */
  repoDir: string
  exec: ExecFn
  /** Resolves a runner-local asset id (the corpus root) to a directory. */
  resolveDir(assetId: string): string | undefined
  timeoutMs?: number
}

const SCRIPT = 'tools/run-resolver-calibration.sh'

export async function preflightResolverCalibration(d: Pick<CalibrationDeps, 'platform' | 'repoDir' | 'exec'>): Promise<{ ok: true } | { ok: false; reason: string }> {
  if (d.platform !== 'darwin') return { ok: false, reason: `needs macOS (xcrun swiftc); this runner is ${d.platform}` }
  if (!existsSync(join(d.repoDir, SCRIPT))) return { ok: false, reason: 'TAKE_LAYER_REPO does not contain tools/run-resolver-calibration.sh' }
  const r = await d.exec('bash', [join(d.repoDir, SCRIPT), '--help'], { timeoutMs: 15 * 60_000, cwd: d.repoDir })
  return r.code === 0 ? { ok: true } : { ok: false, reason: 'the calibration CLI did not compile/run on this machine (--help exited non-zero)' }
}

export function resolverCalibrationHandler(d: CalibrationDeps): JobHandler {
  return {
    jobType: 'RESOLVER_CALIBRATION',
    async run(ctx) {
      const params = ResolverCalibrationParametersSchema.safeParse(ctx.job.parameters)
      if (!params.success) throw new HandlerError('INVALID_PARAMETERS', params.error.issues[0]?.message ?? 'invalid parameters')
      if (ctx.job.inputAssetRefs.length !== 1) throw new HandlerError('INVALID_INPUT', 'RESOLVER_CALIBRATION takes exactly one input asset: the corpus manifest')
      const manifestRef = ctx.job.inputAssetRefs[0]!
      if (manifestRef.locationType !== 'runner-local' || manifestRef.runnerId !== ctx.runnerId) throw new HandlerError('ASSET_NOT_ON_THIS_RUNNER', 'the manifest must be a runner-local asset of this runner')
      const manifest = ctx.resolveAsset(manifestRef)
      const root = d.resolveDir(params.data.corpusRootAssetId)
      if (!manifest || !root) throw new HandlerError('ASSET_NOT_FOUND', 'this runner has no local manifest or corpus root registered for the given asset ids', true)

      const out = await mkdtemp(join(tmpdir(), 'aos-calibration-'))
      try {
        const dataset = join(out, 'derived-dataset.json')
        const report = join(out, 'report.json')
        const args = [join(d.repoDir, SCRIPT), '--manifest', manifest, '--root', root, '--dataset', dataset, '--report', report]
        if (params.data.thresholds?.length) args.push('--thresholds', params.data.thresholds.join(','))
        await ctx.progress(0.1, 'running calibration')
        const r = await d.exec('bash', args, { timeoutMs: d.timeoutMs ?? 55 * 60_000, cwd: d.repoDir })
        if (r.code !== 0) throw new HandlerError('CALIBRATION_FAILED', `the calibration CLI exited with code ${r.code}`, false)
        let raw: Buffer
        try {
          raw = await readFile(report)
          if ((await stat(report)).size > 50 * 1024 * 1024) throw new Error('report too large')
        } catch {
          throw new HandlerError('REPORT_MISSING', 'the CLI succeeded but produced no readable report', false)
        }
        let parsed: unknown
        try {
          parsed = JSON.parse(raw.toString('utf8'))
        } catch {
          throw new HandlerError('REPORT_MALFORMED', 'the report is not valid JSON', false)
        }
        let payload
        try {
          payload = summarizeCalibrationReport(parsed, raw, d.platform, createHash('sha256').update(raw).digest('hex'))
        } catch {
          throw new HandlerError('REPORT_MALFORMED', 'the report does not have the expected summary fields', false)
        }
        const artifact = ResolverCalibrationArtifactSchema.parse({
          schemaVersion: 1,
          artifactId: `art_${ctx.job.jobId}`,
          kind: 'ResolverCalibrationSummaryArtifact',
          producer: 'mac-runner',
          createdAt: new Date().toISOString(),
          subjectRefs: ctx.job.subjectRefs,
          traceId: ctx.job.traceId,
          payloadVersion: CALIBRATION_ARTIFACT_VERSION,
          payload,
        })
        return { artifacts: [artifact] }
      } finally {
        // The derived dataset and report describe a private corpus: they do not outlive the job.
        await rm(out, { recursive: true, force: true })
      }
    },
  }
}
