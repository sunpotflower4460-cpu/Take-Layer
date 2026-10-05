import { AudioAnalysisArtifactV1Schema, AudioAnalysisPayloadSchema } from '../artifacts/audio-analysis.js'
import { ResolverCalibrationArtifactSchema, ResolverCalibrationSummaryPayloadSchema } from '../artifacts/resolver-calibration.js'
import { RenderedMediaArtifactV1Schema, RenderedMediaPayloadSchema } from '../artifacts/render.js'
import { ArtifactEnvelopeSchema } from '../artifacts/pipeline.js'
import type { JobType } from './job.js'

const MAX_ARTIFACT_BYTES = 64 * 1024

/** The artifact kinds each job type may return, with the payload schema that must accept them. */
const EXPECTED: Partial<Record<JobType, { kind: string; payload: { safeParse(v: unknown): { success: boolean; error?: { issues: { message: string }[] } } } }>> = {
  AUDIO_ANALYSIS: { kind: 'AudioAnalysisArtifact', payload: AudioAnalysisPayloadSchema },
  RESOLVER_CALIBRATION: { kind: 'ResolverCalibrationSummaryArtifact', payload: ResolverCalibrationSummaryPayloadSchema },
  RENDER_EDIT_PLAN: { kind: 'RenderedMediaArtifact', payload: RenderedMediaPayloadSchema },
}

export type ResultCheck = { ok: true } | { ok: false; code: 'INVALID_RESULT'; message: string }

/**
 * Server-side acceptance of a Runner's inline results. A Runner is untrusted input: nothing is accepted as
 * COMPLETED unless the artifact has the right kind, parses against the job type's schema, is small, and carries
 * no raw media marker.
 */
export function validateJobResults(jobType: JobType, artifacts: readonly unknown[]): ResultCheck {
  const exp = EXPECTED[jobType]
  if (!exp) return { ok: false, code: 'INVALID_RESULT', message: `no result schema is registered for ${jobType}` }
  if (artifacts.length === 0) return { ok: false, code: 'INVALID_RESULT', message: 'no result artifact' }
  for (const a of artifacts) {
    const env = ArtifactEnvelopeSchema.safeParse(a)
    if (!env.success) return { ok: false, code: 'INVALID_RESULT', message: `invalid artifact envelope: ${env.error.issues[0]?.message}` }
    if (env.data.kind !== exp.kind) return { ok: false, code: 'INVALID_RESULT', message: `expected ${exp.kind}, got ${env.data.kind}` }
    if (JSON.stringify(env.data).length > MAX_ARTIFACT_BYTES) return { ok: false, code: 'INVALID_RESULT', message: 'artifact too large (results are measurements, not media)' }
    if (jobType === 'AUDIO_ANALYSIS') {
      // The full V1 artifact contract (producer, versions, strict payload), not just the payload.
      const full = AudioAnalysisArtifactV1Schema.safeParse(a)
      if (!full.success) return { ok: false, code: 'INVALID_RESULT', message: `invalid AudioAnalysisArtifactV1: ${full.error.issues[0]?.path.join('.')}: ${full.error.issues[0]?.message}` }
    }
    if (jobType === 'RENDER_EDIT_PLAN') {
      const full = RenderedMediaArtifactV1Schema.safeParse(a)
      if (!full.success) return { ok: false, code: 'INVALID_RESULT', message: `invalid RenderedMediaArtifactV1: ${full.error.issues[0]?.path.join('.')}: ${full.error.issues[0]?.message}` }
    }
    if (jobType === 'RESOLVER_CALIBRATION' && !ResolverCalibrationArtifactSchema.safeParse(a).success) return { ok: false, code: 'INVALID_RESULT', message: 'invalid ResolverCalibrationSummaryArtifact' }
    const p = exp.payload.safeParse(env.data.payload)
    if (!p.success) return { ok: false, code: 'INVALID_RESULT', message: `invalid payload: ${p.error?.issues[0]?.message}` }
  }
  return { ok: true }
}
