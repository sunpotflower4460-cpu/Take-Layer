import { z } from 'zod'
import type { RiskClass } from '../policy/gateway.js'

/**
 * Artist OS MCP server — DOMAIN capability definitions only.
 *
 * Transport (stdio / streamable HTTP / SDK) is a thin adapter that maps a tool call
 * to `handler(input)`. Domain logic never imports an MCP SDK, so the capability set
 * can be exposed over any transport — or none — without change.
 * No tool proxies raw vendor tools; none accepts a command or a raw credential.
 */
export interface DomainTool<I extends z.ZodType = z.ZodType, O = unknown> {
  name: string
  description: string
  input: I
  risk: RiskClass
  /** `implemented:false` tools are listed but fail closed with a typed "not_implemented" result. */
  implemented: boolean
  handler?: (input: z.output<I>) => Promise<O> | O
}

export type ToolResult<O> = { ok: true; value: O } | { ok: false; error: 'not_implemented' | 'invalid_input' | 'policy_denied' | 'handler_error'; detail: string }

export class DomainToolRegistry {
  private readonly tools = new Map<string, DomainTool>()
  register<I extends z.ZodType, O>(tool: DomainTool<I, O>): this {
    this.tools.set(tool.name, tool as unknown as DomainTool)
    return this
  }
  list() {
    return [...this.tools.values()].map((t) => ({ name: t.name, description: t.description, risk: t.risk, implemented: t.implemented }))
  }
  async call(name: string, rawInput: unknown, allow: (risk: RiskClass, tool: string) => boolean): Promise<ToolResult<unknown>> {
    const tool = this.tools.get(name)
    if (!tool) return { ok: false, error: 'invalid_input', detail: `unknown tool ${name}` }
    if (!tool.implemented || !tool.handler) return { ok: false, error: 'not_implemented', detail: `${name} is declared but not implemented` }
    const parsed = tool.input.safeParse(rawInput)
    if (!parsed.success) return { ok: false, error: 'invalid_input', detail: parsed.error.issues[0]?.message ?? 'invalid' }
    if (!allow(tool.risk, name)) return { ok: false, error: 'policy_denied', detail: `${tool.risk} not permitted for ${name}` }
    try {
      return { ok: true, value: await tool.handler(parsed.data) }
    } catch (e) {
      return { ok: false, error: 'handler_error', detail: e instanceof Error ? e.message.slice(0, 200) : 'error' }
    }
  }
}

const empty = z.object({})
const releaseInput = z.object({ releaseId: z.string().min(1) })

/** The planned tool surface (§20). Only read-only projection tools get handlers; the rest are honest stubs. */
export const PLANNED_TOOLS: DomainTool[] = [
  { name: 'get_today', description: 'Today projection (auto-completed / running / needs you / scheduled).', input: empty, risk: 'READ', implemented: false },
  { name: 'get_release_status', description: 'Release dashboard for one release.', input: releaseInput, risk: 'READ', implemented: false },
  { name: 'get_attention_items', description: 'Attention Queue projection.', input: empty, risk: 'READ', implemented: false },
  { name: 'get_runner_status', description: 'Mac Runner registry and queue state.', input: empty, risk: 'READ', implemented: false },
  { name: 'research_youtube', description: 'Request youtube.market_research via the Capability Router.', input: empty, risk: 'GENERATE', implemented: false },
  { name: 'research_music_market', description: 'Request music.market_intelligence via the Capability Router.', input: empty, risk: 'GENERATE', implemented: false },
  { name: 'prepare_short_variants', description: 'Queue GENERATE_SHORT_VARIANTS Mac job (prepare only).', input: releaseInput, risk: 'WRITE_REVERSIBLE', implemented: false },
  { name: 'prepare_social_campaign', description: 'Ask SNS-AI for a strategy ARTIFACT (no publishing).', input: releaseInput, risk: 'GENERATE', implemented: false },
  { name: 'review_music_growth', description: 'Read My-Spotify growth status for a release.', input: releaseInput, risk: 'READ', implemented: false },
]
