import type { JobType } from '../job.js'
import { audioAnalysisHandler } from './audio-analysis.js'
import type { JobHandler } from './types.js'

export * from './types.js'

/**
 * The handlers this build REALLY has. Everything else in JOB_TYPES (video render, lyrics alignment, edit proposals, …)
 * is deliberately absent: the Runner will not advertise it and the queue will not offer it.
 */
export const REGISTERED_HANDLERS: readonly JobHandler[] = [audioAnalysisHandler]

export const handlerFor = (jobType: JobType, handlers: readonly JobHandler[] = REGISTERED_HANDLERS) => handlers.find((h) => h.jobType === jobType)
