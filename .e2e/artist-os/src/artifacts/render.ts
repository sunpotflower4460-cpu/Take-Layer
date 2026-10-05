import { createHash } from 'node:crypto'
import { z } from 'zod'
import { AssetRefSchema } from '../core/asset.js'
import { ArtifactEnvelopeSchema } from './pipeline.js'
import { IsoTimestampSchema, OpaqueIdSchema } from '../core/common.js'

/**
 * RENDER_EDIT_PLAN — deterministic render of an EXISTING editing plan (Take-Layer's ShortEditDraft) to MP4 on a Mac.
 *
 *   Artist OS  →  Mac job (typed parameters, runner-local asset ids)  →  Take-Layer headless renderer  →  local MP4
 *   result     →  RenderedMediaArtifactV1 (measurements + a runner-local reference; the video itself never leaves the Mac)
 *
 * No AI is involved: the plan is explicit input and the output is a function of (plan, sources, renderer).
 * The plan fields are exactly Take-Layer's ShortEditDraft (range, zoom, focusX/Y, title, lyric cues): Artist OS adds
 * a snapshot (id/version/hash) so "which plan produced this video" stays answerable after the plan changes.
 */
export const RENDERED_MEDIA_ARTIFACT_VERSION = 1 as const
/** Render profile baked into the semantic dedupe key: a different profile is a different render. */
export const RENDER_PROFILE = 'short-1080x1920-30fps-h264-v1'

const finite = z.number().refine(Number.isFinite, 'must be finite')

export const ShortEditPlanSchema = z
  .object({
    rangeStartProjectSec: finite.pipe(z.number().min(0)),
    rangeEndProjectSec: finite.pipe(z.number().min(0)),
    titleText: z.string().max(200),
    crop: z.object({ zoom: z.number().min(1).max(3), focusX: z.number().min(0).max(1), focusY: z.number().min(0).max(1) }).strict(),
    lyricCues: z.array(z.object({ startProjectSec: finite, endProjectSec: finite, text: z.string().max(200) }).strict()).max(200),
  })
  .strict()
  .superRefine((p, ctx) => {
    const d = p.rangeEndProjectSec - p.rangeStartProjectSec
    if (!(d > 0)) ctx.addIssue({ code: 'custom', path: ['rangeEndProjectSec'], message: 'the range must have positive length' })
    if (d > 180) ctx.addIssue({ code: 'custom', path: ['rangeEndProjectSec'], message: 'a Short is at most 180 s' })
  })
export type ShortEditPlan = z.infer<typeof ShortEditPlanSchema>

export const TimelineSchema = z.object({ songStartRawSec: finite.pipe(z.number().min(0)), songStartAudioSec: finite.pipe(z.number().min(0)), offsetMs: finite }).strict()
export type RenderTimeline = z.infer<typeof TimelineSchema>

const Sha256Schema = z.string().regex(/^sha256:[0-9a-f]{64}$/)

export const EditingPlanSnapshotSchema = z.object({ planId: OpaqueIdSchema, planVersion: z.number().int().min(1), planHash: Sha256Schema }).strict()
export type EditingPlanSnapshot = z.infer<typeof EditingPlanSnapshotSchema>

/** Facts about the sources that Take-Layer's TimelineMapper needs; the Mac re-measures and refuses on a mismatch. */
export const SourceFactsSchema = z
  .object({
    video: z.object({ durationSec: z.number().positive(), width: z.number().int().positive().optional(), height: z.number().int().positive().optional() }).strict(),
    masterAudio: z.object({ durationSec: z.number().positive(), sampleRate: z.number().positive().optional(), channelCount: z.number().int().positive().optional() }).strict(),
  })
  .strict()

export const RenderEditPlanParametersSchema = z.object({ plan: EditingPlanSnapshotSchema, edit: ShortEditPlanSchema, timeline: TimelineSchema, sources: SourceFactsSchema, profile: z.literal(RENDER_PROFILE).default(RENDER_PROFILE) }).strict()
export type RenderEditPlanParameters = z.infer<typeof RenderEditPlanParametersSchema>

/** Key-order-independent JSON so a hash does not depend on how an object was built. */
export function canonicalJson(v: unknown): string {
  return JSON.stringify(v, (_k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) : x))
}
export const sha256Of = (s: string) => `sha256:${createHash('sha256').update(s).digest('hex')}`

/** The plan hash covers everything that changes the picture or sound; planId/planVersion are labels. */
export const computePlanHash = (edit: ShortEditPlan, timeline: RenderTimeline): string => sha256Of(canonicalJson({ edit, timeline }))

/**
 * Semantic dedupe key. The same plan on the same source bytes with the same render profile is the same request,
 * even though an encoder may not produce a binary-identical MP4.
 */
export function renderRequestKey(planHash: string, videoHash: string, audioHash: string): string {
  return `render:${createHash('sha256').update(canonicalJson({ planHash, videoHash, audioHash, profile: RENDER_PROFILE })).digest('hex').slice(0, 48)}`
}

export const RenderCheckSchema = z.object({ name: z.string().max(64), ok: z.boolean(), detail: z.string().max(200) }).strict()

export const RenderedMediaPayloadSchema = z
  .object({
    sourceAssetRefs: z.array(z.object({ role: z.enum(['video', 'master_wav']), assetRef: OpaqueIdSchema, contentHash: Sha256Schema }).strict()).length(2),
    editingPlanRef: EditingPlanSnapshotSchema,
    /** A runner-local reference. The video stays on the Mac; `locationId` is opaque (AssetRef refuses filesystem paths). */
    outputAssetRef: AssetRefSchema,
    contentHash: Sha256Schema,
    sizeBytes: z.number().int().positive(),
    durationSec: z.number().positive(),
    width: z.number().int().positive(),
    height: z.number().int().positive(),
    fps: z.number().positive(),
    renderer: z.string().min(1).max(64),
    rendererVersion: z.string().min(1).max(32),
    profile: z.literal(RENDER_PROFILE),
    /** Where the program audio came from. By construction the renderer inserts only the master WAV track. */
    audioSource: z.literal('master_wav'),
    validation: z.object({ checks: z.array(RenderCheckSchema).min(1).max(20), passed: z.literal(true) }).strict(),
    renderedAt: IsoTimestampSchema,
  })
  .strict()
  .superRefine((p, ctx) => {
    if (p.outputAssetRef.locationType !== 'runner-local') ctx.addIssue({ code: 'custom', path: ['outputAssetRef'], message: 'rendered output stays runner-local (no upload in this phase)' })
    if (p.outputAssetRef.contentHash !== p.contentHash) ctx.addIssue({ code: 'custom', path: ['outputAssetRef', 'contentHash'], message: 'outputAssetRef.contentHash must equal contentHash' })
    if (p.validation.checks.some((c) => !c.ok)) ctx.addIssue({ code: 'custom', path: ['validation'], message: 'a failed quality check cannot be part of an accepted artifact' })
    const roles = new Set(p.sourceAssetRefs.map((s) => s.role))
    if (roles.size !== 2) ctx.addIssue({ code: 'custom', path: ['sourceAssetRefs'], message: 'exactly one video and one master_wav source' })
  })
export type RenderedMediaPayload = z.infer<typeof RenderedMediaPayloadSchema>

export const RenderedMediaArtifactV1Schema = ArtifactEnvelopeSchema.extend({
  kind: z.literal('RenderedMediaArtifact'),
  producer: z.literal('mac-runner'),
  payloadVersion: z.literal(RENDERED_MEDIA_ARTIFACT_VERSION),
  payload: RenderedMediaPayloadSchema,
})
export type RenderedMediaArtifactV1 = z.infer<typeof RenderedMediaArtifactV1Schema>
