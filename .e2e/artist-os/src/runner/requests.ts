import { z } from 'zod'
import type { AssetRef } from '../core/asset.js'
import { AssetRefSchema } from '../core/asset.js'
import type { SourceRef } from '../core/common.js'
import { EditingPlanSnapshotSchema, RENDER_PROFILE, RenderEditPlanParametersSchema, ShortEditPlanSchema, SourceFactsSchema, TimelineSchema, computePlanHash, renderRequestKey } from '../artifacts/render.js'
import type { EnqueueInput } from './queue-port.js'

/**
 * Pre-enqueue validation for RENDER_EDIT_PLAN. A bad request is refused HERE, before a job exists:
 * a Mac never gets to render something the server already knew was inconsistent.
 */
export const RenderRequestSchema = z
  .object({
    workspaceRef: z.string().min(1),
    plan: EditingPlanSnapshotSchema,
    edit: ShortEditPlanSchema,
    timeline: TimelineSchema,
    sources: SourceFactsSchema,
    video: AssetRefSchema,
    masterAudio: AssetRefSchema,
    subjectRefs: z.array(z.custom<SourceRef>()).max(19).optional(),
    traceId: z.string().optional(),
    causationId: z.string().optional(),
  })
  .strict()
export type RenderRequest = z.infer<typeof RenderRequestSchema>

export type RenderRequestRejection = 'INVALID_REQUEST' | 'PLAN_HASH_MISMATCH' | 'ASSET_HASH_REQUIRED' | 'ASSET_NOT_RUNNER_LOCAL' | 'ASSET_KIND_MISMATCH' | 'ASSETS_ON_DIFFERENT_RUNNERS'
export type BuiltRender = { ok: true; input: EnqueueInput & { idempotencyKey: string } } | { ok: false; code: RenderRequestRejection; detail: string }

const reject = (code: RenderRequestRejection, detail: string): BuiltRender => ({ ok: false, code, detail })

export function buildRenderEnqueue(raw: unknown): BuiltRender {
  const p = RenderRequestSchema.safeParse(raw)
  if (!p.success) return reject('INVALID_REQUEST', `${p.error.issues[0]?.path.join('.')}: ${p.error.issues[0]?.message}`)
  const r = p.data
  // The plan snapshot is fixed at request time: a hash that does not match the content is refused, never "fixed".
  const actual = computePlanHash(r.edit, r.timeline)
  if (actual !== r.plan.planHash) return reject('PLAN_HASH_MISMATCH', 'plan.planHash does not match the edit + timeline content')
  const refs: [string, AssetRef, 'raw_video' | 'master_wav'][] = [
    ['video', r.video, 'raw_video'],
    ['masterAudio', r.masterAudio, 'master_wav'],
  ]
  for (const [name, ref, kind] of refs) {
    if (ref.locationType !== 'runner-local') return reject('ASSET_NOT_RUNNER_LOCAL', `${name} must be a runner-local asset (the Mac resolves it; no path or upload here)`)
    if (ref.kind !== kind) return reject('ASSET_KIND_MISMATCH', `${name} must be a ${kind}`)
    if (!ref.contentHash) return reject('ASSET_HASH_REQUIRED', `${name} needs a contentHash so the Mac can verify the bytes it renders`)
  }
  if (r.video.runnerId !== r.masterAudio.runnerId) return reject('ASSETS_ON_DIFFERENT_RUNNERS', 'both sources must be on the same Mac')
  const parameters = RenderEditPlanParametersSchema.parse({ plan: r.plan, edit: r.edit, timeline: r.timeline, sources: r.sources, profile: RENDER_PROFILE })
  return {
    ok: true,
    input: {
      jobType: 'RENDER_EDIT_PLAN',
      workspaceRef: r.workspaceRef,
      subjectRefs: r.subjectRefs ?? [],
      inputAssetRefs: [r.video, r.masterAudio],
      parameters: parameters as never,
      idempotencyKey: renderRequestKey(r.plan.planHash, r.video.contentHash!, r.masterAudio.contentHash!),
      traceId: r.traceId,
      causationId: r.causationId,
    },
  }
}
