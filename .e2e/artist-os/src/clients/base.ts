import type { z } from 'zod'
import { type ActionTarget, type ServiceHealth, ServiceHealthSchema, type ServiceStatusReport, ServiceStatusReportSchema } from '../contracts/service.js'
import type { SystemId } from '../core/common.js'

export type ClientFailureReason =
  | 'not_configured'
  | 'unauthorized'
  | 'timeout'
  | 'network'
  | 'http_error'
  | 'invalid_response' // contract violation: response failed schema validation
  | 'contract_mismatch' // wrong service id / contract version

export type ClientResult<T> = { ok: true; value: T } | { ok: false; reason: ClientFailureReason; detail: string; httpStatus?: number }

export interface SpecialistClientOptions {
  service: SystemId
  baseUrl?: string
  /** Service token. Held privately, sent only as a Bearer header, never logged or returned. */
  token?: string
  fetchImpl?: typeof fetch
  timeoutMs?: number
  /** Cap on body size we are willing to parse (bytes). */
  maxBodyBytes?: number
}

/**
 * Bounded, read-first HTTP client for one specialist. Artist OS never connects
 * to a specialist database; this is the only door. All failures are returned as
 * typed results (fail closed), and responses are schema-validated — a
 * specialist response is untrusted input until it parses.
 */
export class SpecialistClient {
  protected readonly fetchImpl: typeof fetch
  protected readonly timeoutMs: number
  protected readonly maxBodyBytes: number

  constructor(protected readonly opts: SpecialistClientOptions) {
    this.fetchImpl = opts.fetchImpl ?? fetch
    this.timeoutMs = opts.timeoutMs ?? 5000
    this.maxBodyBytes = opts.maxBodyBytes ?? 1_000_000
  }

  get service(): SystemId {
    return this.opts.service
  }

  async health(): Promise<ClientResult<ServiceHealth>> {
    const r = await this.getJson('/api/service/health', ServiceHealthSchema, false)
    if (!r.ok) return r
    if (r.value.service !== this.opts.service) {
      return { ok: false, reason: 'contract_mismatch', detail: `expected ${this.opts.service}, got ${r.value.service}` }
    }
    return r
  }

  async status(): Promise<ClientResult<ServiceStatusReport>> {
    const r = await this.getJson('/api/service/v1/status', ServiceStatusReportSchema, true)
    if (!r.ok) return r
    if (r.value.service !== this.opts.service) {
      return { ok: false, reason: 'contract_mismatch', detail: `expected ${this.opts.service}, got ${r.value.service}` }
    }
    return r
  }

  /**
   * Forwards a human decision to the specialist's OWN approval endpoint.
   * The target URL comes from specialist-supplied data (untrusted), so it must be
   * same-origin with the configured baseUrl — the service token is never sent elsewhere.
   * Artist OS records nothing as "approved" itself; the specialist's response is the truth.
   */
  async forwardAction(target: Extract<ActionTarget, { type: 'endpoint' }>, body: Record<string, unknown>): Promise<ClientResult<{ status: number }>> {
    if (!this.opts.baseUrl || !this.opts.token) return { ok: false, reason: 'not_configured', detail: `${this.opts.service} not configured for actions` }
    let url: URL
    try {
      url = new URL(target.url)
    } catch {
      return { ok: false, reason: 'invalid_response', detail: 'bad action url' }
    }
    if (url.origin !== new URL(this.opts.baseUrl).origin) {
      return { ok: false, reason: 'invalid_response', detail: 'action url origin differs from service baseUrl; refusing to send credentials' }
    }
    const ctl = new AbortController()
    const timer = setTimeout(() => ctl.abort(), this.timeoutMs)
    try {
      const res = await this.fetchImpl(url.toString(), {
        method: target.method,
        headers: { 'content-type': 'application/json', authorization: `Bearer ${this.opts.token}` },
        body: JSON.stringify({ ...body, ...(target.bindingToken ? { bindingToken: target.bindingToken } : {}) }),
        signal: ctl.signal,
        redirect: 'error',
      })
      if (res.status === 401 || res.status === 403) return { ok: false, reason: 'unauthorized', detail: `HTTP ${res.status}`, httpStatus: res.status }
      // 202/409 etc. are the specialist's answer (e.g. UNKNOWN_RESULT, STALE_APPROVAL): never retried blindly.
      if (!res.ok) return { ok: false, reason: 'http_error', detail: `HTTP ${res.status}`, httpStatus: res.status }
      return { ok: true, value: { status: res.status } }
    } catch (e) {
      const aborted = e instanceof Error && e.name === 'AbortError'
      // A timeout on a write is an UNCERTAIN outcome: caller must reconcile with the specialist before any retry.
      return { ok: false, reason: aborted ? 'timeout' : 'network', detail: aborted ? 'uncertain outcome: reconcile before retry' : 'request failed' }
    } finally {
      clearTimeout(timer)
    }
  }

  async getJson<S extends z.ZodType>(path: string, schema: S, auth: boolean): Promise<ClientResult<z.output<S>>> {
    if (!this.opts.baseUrl) return { ok: false, reason: 'not_configured', detail: `${this.opts.service} has no baseUrl` }
    if (auth && !this.opts.token) return { ok: false, reason: 'not_configured', detail: `${this.opts.service} has no service token` }
    const ctl = new AbortController()
    const timer = setTimeout(() => ctl.abort(), this.timeoutMs)
    try {
      const res = await this.fetchImpl(new URL(path, this.opts.baseUrl).toString(), {
        method: 'GET',
        headers: { accept: 'application/json', ...(auth ? { authorization: `Bearer ${this.opts.token}` } : {}) },
        signal: ctl.signal,
        redirect: 'error',
      })
      if (res.status === 401 || res.status === 403) return { ok: false, reason: 'unauthorized', detail: `HTTP ${res.status}`, httpStatus: res.status }
      if (!res.ok) return { ok: false, reason: 'http_error', detail: `HTTP ${res.status}`, httpStatus: res.status }
      const text = await res.text()
      if (text.length > this.maxBodyBytes) return { ok: false, reason: 'invalid_response', detail: 'body too large' }
      let json: unknown
      try {
        json = JSON.parse(text)
      } catch {
        return { ok: false, reason: 'invalid_response', detail: 'not JSON' }
      }
      const parsed = schema.safeParse(json)
      if (!parsed.success) return { ok: false, reason: 'invalid_response', detail: parsed.error.issues[0]?.message ?? 'schema mismatch' }
      return { ok: true, value: parsed.data }
    } catch (e) {
      const aborted = e instanceof Error && e.name === 'AbortError'
      return { ok: false, reason: aborted ? 'timeout' : 'network', detail: aborted ? `>${this.timeoutMs}ms` : 'request failed' }
    } finally {
      clearTimeout(timer)
    }
  }
}
