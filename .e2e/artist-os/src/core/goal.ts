import { z } from 'zod'
import { IsoTimestampSchema, OpaqueIdSchema, SCHEMA_VERSION } from './common.js'

export const GOAL_PRIORITIES = ['low', 'medium', 'high'] as const
export const GOAL_STATUSES = ['active', 'paused', 'achieved', 'abandoned'] as const

/**
 * Goal answers "what are we prioritizing now?".
 * Brand Profile (My-SNS) answers "who am I / how do I communicate?" and is NOT stored here.
 */
export const GoalSchema = z.object({
  schemaVersion: z.literal(SCHEMA_VERSION),
  goalId: OpaqueIdSchema,
  workspaceRef: OpaqueIdSchema,
  title: z.string().trim().min(1).max(200),
  objective: z.string().trim().max(1000).default(''),
  priority: z.enum(GOAL_PRIORITIES),
  status: z.enum(GOAL_STATUSES),
  /** Human-authored hard constraints. Specialists must treat these as outranking numeric growth. */
  constraints: z.array(z.string().trim().min(1).max(300)).max(30).default([]),
  startsAt: IsoTimestampSchema.optional(),
  endsAt: IsoTimestampSchema.optional(),
  createdAt: IsoTimestampSchema,
  updatedAt: IsoTimestampSchema,
})
export type Goal = z.infer<typeof GoalSchema>

export const NewGoalInputSchema = GoalSchema.pick({
  workspaceRef: true,
  title: true,
  priority: true,
}).extend({
  objective: z.string().trim().max(1000).optional(),
  constraints: z.array(z.string().trim().min(1).max(300)).max(30).optional(),
  startsAt: IsoTimestampSchema.optional(),
  endsAt: IsoTimestampSchema.optional(),
})
export type NewGoalInput = z.input<typeof NewGoalInputSchema>

/** At most one active goal per workspace is "the" current goal: the highest priority, then most recently updated. */
export function pickCurrentGoal(goals: readonly Goal[]): Goal | undefined {
  const rank = { high: 3, medium: 2, low: 1 } as const
  return goals
    .filter((g) => g.status === 'active')
    .sort((a, b) => rank[b.priority] - rank[a.priority] || b.updatedAt.localeCompare(a.updatedAt))[0]
}
