import { z } from 'zod'
import { ArtifactEnvelopeSchema } from './pipeline.js'

/**
 * ResolverCalibrationSummaryArtifact — the result of the Mac job RESOLVER_CALIBRATION (Take-Layer's headless
 * resolver calibration CLI). PRIVACY: the CLI works on a private audio corpus and its report contains dataset and
 * per-case detail. The artifact carries ONLY aggregate numbers plus the hash/size of the full report (which stays on
 * the Mac): no dataset name, no case/file names, no nested observations, no audio.
 */
export const CALIBRATION_ARTIFACT_VERSION = 1 as const

export const ResolverCalibrationSummaryPayloadSchema = z
  .object({
    reportSha256: z.string().regex(/^sha256:[0-9a-f]{64}$/),
    reportBytes: z.number().int().nonnegative(),
    totalCases: z.number().int().nonnegative(),
    minimumPositiveConfidence: z.number().nullable(),
    maximumNegativeConfidence: z.number().nullable(),
    /** Positive ⇒ same-song and different-song confidence ranges do not overlap. null = not computable (e.g. no negatives). */
    confidenceGap: z.number().nullable(),
    /** Numeric-only metrics per threshold; unknown/nested/string fields are dropped. */
    thresholdMetrics: z.array(z.record(z.string().max(48), z.number())).max(20),
    tool: z.object({ name: z.literal('take-layer-resolver-calibration'), runnerPlatform: z.string().max(16) }),
  })
  .strict()
export type ResolverCalibrationSummaryPayload = z.infer<typeof ResolverCalibrationSummaryPayloadSchema>

export const ResolverCalibrationArtifactSchema = ArtifactEnvelopeSchema.extend({
  kind: z.literal('ResolverCalibrationSummaryArtifact'),
  producer: z.literal('mac-runner'),
  payloadVersion: z.literal(CALIBRATION_ARTIFACT_VERSION),
  payload: ResolverCalibrationSummaryPayloadSchema,
})

export const ResolverCalibrationParametersSchema = z.object({
  /** Confidence thresholds to evaluate (each 0..1). Omitted ⇒ the CLI's own defaults. */
  thresholds: z.array(z.number().min(0).max(1)).max(20).optional(),
  /** Runner-local asset id of the corpus ROOT directory (resolved on the Mac; the path never leaves it). */
  corpusRootAssetId: z.string().min(1).max(128),
})
export type ResolverCalibrationParameters = z.infer<typeof ResolverCalibrationParametersSchema>

/** Reduces the full report to the privacy-safe summary. Pure. */
export function summarizeCalibrationReport(report: unknown, rawBytes: Buffer, runnerPlatform: string, sha256: string): ResolverCalibrationSummaryPayload {
  const r = (report && typeof report === 'object' ? report : {}) as Record<string, unknown>
  const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
  const total = num(r.totalCases)
  if (total === null || !Number.isInteger(total) || total < 0) throw new Error('report has no valid totalCases')
  const tm = Array.isArray(r.thresholdMetrics) ? r.thresholdMetrics : []
  const thresholdMetrics = tm.slice(0, 20).map((m) => {
    const out: Record<string, number> = {}
    if (m && typeof m === 'object') for (const [k, v] of Object.entries(m as Record<string, unknown>)) if (k.length <= 48 && typeof v === 'number' && Number.isFinite(v)) out[k] = v
    return out
  })
  return {
    reportSha256: `sha256:${sha256}`,
    reportBytes: rawBytes.length,
    totalCases: total,
    minimumPositiveConfidence: num(r.minimumPositiveConfidence),
    maximumNegativeConfidence: num(r.maximumNegativeConfidence),
    confidenceGap: num(r.confidenceGap),
    thresholdMetrics,
    tool: { name: 'take-layer-resolver-calibration', runnerPlatform },
  }
}
