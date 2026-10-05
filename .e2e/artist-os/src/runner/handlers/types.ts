import type { ArtifactEnvelope } from '../../artifacts/pipeline.js'
import type { AssetRef } from '../../core/asset.js'
import type { JobType, MacJob } from '../job.js'

export interface HandlerContext {
  job: MacJob
  runnerId: string
  /** Maps a runner-local AssetRef to a local path. Returns undefined when this runner does not hold it. Paths never leave the runner. */
  resolveAsset(ref: AssetRef): string | undefined
  progress(fraction: number, stage: string): Promise<void>
}

export class HandlerError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly retryable = false,
  ) {
    super(message)
    this.name = 'HandlerError'
  }
}

/**
 * A typed job handler. A job type is "supported" by a Runner ONLY if a real handler is registered:
 * stubs are not registered, so they are never advertised and the queue never offers them.
 */
export interface JobHandler {
  jobType: JobType
  run(ctx: HandlerContext): Promise<{ artifacts: ArtifactEnvelope[] }>
  /**
   * Local-write handlers only: LOOK at what the interrupted run left on this Mac and say what is true.
   * Must be read-only apart from deleting its own abandoned partial files. Never "assume".
   */
  reconcile?(ctx: HandlerContext): Promise<ReconcileReport>
}

export type ReconcileReport =
  | { outcome: 'completed'; evidence: string; artifacts: ArtifactEnvelope[] }
  | { outcome: 'not_completed'; evidence: string }
  | { outcome: 'ambiguous'; evidence: string }
