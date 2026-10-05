import type { ArtifactEnvelope } from '../../artifacts/pipeline.js'
import { AudioAnalysisArtifactV1Schema, AudioAnalysisParametersSchema, AUDIO_ANALYSIS_ARTIFACT_VERSION } from '../../artifacts/audio-analysis.js'
import { AnalysisError, analyzeWavFile } from './wav-analyzer.js'
import { HandlerError, type JobHandler } from './types.js'

/**
 * AUDIO_ANALYSIS on the Mac. Reads a LOCAL WAV, measures it, returns a versioned artifact.
 * No network access, no model, no upload of audio: this module has no fetch and receives none.
 */
export const audioAnalysisHandler: JobHandler = {
  jobType: 'AUDIO_ANALYSIS',
  async run(ctx) {
    const params = AudioAnalysisParametersSchema.safeParse(ctx.job.parameters)
    if (!params.success) throw new HandlerError('INVALID_PARAMETERS', params.error.issues[0]?.message ?? 'invalid parameters')
    const inputs = ctx.job.inputAssetRefs
    if (inputs.length !== 1) throw new HandlerError('INVALID_INPUT', 'AUDIO_ANALYSIS takes exactly one input asset')
    const ref = inputs[0]!
    if (ref.kind !== 'master_wav' && ref.kind !== 'raw_audio') throw new HandlerError('INVALID_INPUT', `input asset kind ${ref.kind} is not audio`)
    if (ref.locationType !== 'runner-local') throw new HandlerError('INVALID_INPUT', 'input asset must be runner-local; this handler never downloads media')
    if (ref.runnerId !== ctx.runnerId) throw new HandlerError('ASSET_NOT_ON_THIS_RUNNER', 'input asset belongs to a different runner')
    const path = ctx.resolveAsset(ref)
    if (!path) throw new HandlerError('ASSET_NOT_FOUND', 'this runner has no local file registered for the input asset', true)

    await ctx.progress(0.05, 'reading')
    let payload
    try {
      let last = 0
      payload = await analyzeWavFile(path, params.data, {
        expectedHash: ref.contentHash,
        assetRef: ref.assetRef,
        onProgress: (f) => {
          if (f - last >= 0.25) {
            last = f
            void ctx.progress(0.05 + f * 0.9, 'analyzing')
          }
        },
      })
    } catch (e) {
      if (e instanceof AnalysisError) throw new HandlerError(e.code, e.message, e.retryable)
      throw e
    }

    // Verified before it leaves the handler: the artifact must satisfy the V1 contract (strict).
    const artifact: ArtifactEnvelope = AudioAnalysisArtifactV1Schema.parse({
      schemaVersion: 1,
      artifactId: `art_${ctx.job.jobId}`,
      kind: 'AudioAnalysisArtifact',
      producer: 'mac-runner',
      createdAt: new Date().toISOString(),
      subjectRefs: ctx.job.subjectRefs,
      traceId: ctx.job.traceId,
      payloadVersion: AUDIO_ANALYSIS_ARTIFACT_VERSION,
      payload,
    })
    return { artifacts: [artifact] }
  },
}
