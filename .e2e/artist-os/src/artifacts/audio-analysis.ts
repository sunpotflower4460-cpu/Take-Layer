import { z } from 'zod'
import { ArtifactEnvelopeSchema } from './pipeline.js'
import { OpaqueIdSchema } from '../core/common.js'

/**
 * AudioAnalysisArtifactV1 — the formal, versioned result of the AUDIO_ANALYSIS Mac job.
 *
 *   input   a runner-local AssetRef (master_wav | raw_audio); the bytes never leave the Mac
 *   output  measurements only: no audio, no LLM, no estimates
 *
 * Reuse: this is a SHARED job result / piece of evidence, consumable by Take-Layer, My-Spotify and Artist OS.
 * It is NOT anyone's source of truth: Take-Layer's Song Memory and My-Spotify's Track Intelligence stay theirs.
 * A consumer must check `sourceAssetRef.contentHash` against its OWN copy of the asset before relying on it.
 *
 * Honesty rules baked into the schema:
 *  - Measurements the analyzer did not make are not present as 0 or as guesses: `unsupported` lists them by name
 *    with the literal marker "unsupported" (tempo, key, lufs). A consumer reading `unsupported.tempo` cannot mistake it
 *    for a tempo of 0.
 *  - `peakDb`/`rmsDb` are null ONLY for digital silence (log of zero is undefined), and `signal` says so explicitly.
 */
export const AUDIO_ANALYSIS_ARTIFACT_VERSION = 1 as const
export const AUDIO_ANALYSIS_PAYLOAD_VERSION = AUDIO_ANALYSIS_ARTIFACT_VERSION

export const AudioAnalysisParametersSchema = z.object({
  /** A frame is "silent" when every channel's absolute sample is below this level (dBFS). */
  silenceThresholdDb: z.number().min(-120).max(0).default(-60),
  /** Only silent runs at least this long are reported as regions. */
  minSilenceSec: z.number().min(0.01).max(60).default(0.5),
})
export type AudioAnalysisParameters = z.infer<typeof AudioAnalysisParametersSchema>

export const MAX_SILENCE_REGIONS = 500

/** Everything the v1 analyzer deliberately does not measure. Marked, never zero-filled. */
export const AUDIO_UNSUPPORTED = { tempo: 'unsupported', key: 'unsupported', lufs: 'unsupported' } as const

export const SilenceRegionSchema = z
  .object({ startSec: z.number().nonnegative(), endSec: z.number().nonnegative() })
  .refine((r) => r.endSec > r.startSec, { message: 'silence region must have positive length' })

export const AudioAnalysisPayloadSchema = z
  .object({
    /** Which asset was analyzed. `contentHash` is of the file bytes the Mac actually read. */
    sourceAssetRef: z.object({ assetRef: OpaqueIdSchema, contentHash: z.string().regex(/^sha256:[0-9a-f]{64}$/) }),
    contentHash: z.string().regex(/^sha256:[0-9a-f]{64}$/),
    analyzer: z.string().min(1).max(64),
    analyzerVersion: z.string().min(1).max(32),
    format: z.object({
      container: z.literal('wav'),
      encoding: z.enum(['pcm_s16le', 'pcm_s24le', 'pcm_s32le', 'float32']),
      sampleRate: z.number().int().positive(),
      channels: z.number().int().min(1).max(64),
      bitsPerSample: z.number().int(),
    }),
    sizeBytes: z.number().int().nonnegative(),
    frames: z.number().int().nonnegative(),
    durationSec: z.number().nonnegative(),
    signal: z.enum(['audible', 'digital_silence']),
    peakDb: z.number().nullable(),
    rmsDb: z.number().nullable(),
    /** Samples at (or beyond) full scale. */
    clipCount: z.number().int().nonnegative(),
    silenceRegions: z.object({
      thresholdDb: z.number(),
      minSilenceSec: z.number(),
      regions: z.array(SilenceRegionSchema).max(MAX_SILENCE_REGIONS),
      /** true when more regions existed than MAX_SILENCE_REGIONS (the list is a prefix, not the whole truth). */
      truncated: z.boolean(),
      totalSilentSec: z.number().nonnegative(),
    }),
    unsupported: z.object({ tempo: z.literal('unsupported'), key: z.literal('unsupported'), lufs: z.literal('unsupported') }),
  })
  .strict()
  .superRefine((p, ctx) => {
    if (p.contentHash !== p.sourceAssetRef.contentHash) ctx.addIssue({ code: 'custom', path: ['sourceAssetRef', 'contentHash'], message: 'sourceAssetRef.contentHash must equal contentHash of the analyzed bytes' })
    if ((p.signal === 'digital_silence') !== (p.peakDb === null) || (p.peakDb === null) !== (p.rmsDb === null)) ctx.addIssue({ code: 'custom', path: ['signal'], message: 'peak/rms are null exactly when the signal is digital silence' })
    for (const r of p.silenceRegions.regions) if (r.endSec > p.durationSec + 1e-6) ctx.addIssue({ code: 'custom', path: ['silenceRegions'], message: 'silence region beyond the end of the audio' })
  })
export type AudioAnalysisPayload = z.infer<typeof AudioAnalysisPayloadSchema>

/** The whole artifact: the standard envelope with the kind and payload pinned to V1. */
export const AudioAnalysisArtifactV1Schema = ArtifactEnvelopeSchema.extend({
  kind: z.literal('AudioAnalysisArtifact'),
  producer: z.literal('mac-runner'),
  payloadVersion: z.literal(AUDIO_ANALYSIS_ARTIFACT_VERSION),
  payload: AudioAnalysisPayloadSchema,
})
export type AudioAnalysisArtifactV1 = z.infer<typeof AudioAnalysisArtifactV1Schema>

/** For consumers: parse + verify the artifact describes THE asset they hold. */
export function acceptAudioAnalysisFor(raw: unknown, own: { contentHash: string }): { ok: true; artifact: AudioAnalysisArtifactV1 } | { ok: false; reason: 'malformed' | 'hash_mismatch' } {
  const p = AudioAnalysisArtifactV1Schema.safeParse(raw)
  if (!p.success) return { ok: false, reason: 'malformed' }
  if (p.data.payload.contentHash !== own.contentHash) return { ok: false, reason: 'hash_mismatch' }
  return { ok: true, artifact: p.data }
}
