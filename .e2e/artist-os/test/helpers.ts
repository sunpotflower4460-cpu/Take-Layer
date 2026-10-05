import type { Clock } from '../src/index.js'

export const fixedClock = (iso = '2026-10-05T12:00:00.000Z'): { clock: Clock; advance(ms: number): void } => {
  let t = Date.parse(iso)
  return { clock: () => new Date(t), advance: (ms) => void (t += ms) }
}

export const seqIds = () => {
  let n = 0
  return (prefix: string) => `${prefix}_${++n}`
}

/** Scripted fetch: maps "METHOD url" → response factory. Unknown ⇒ network failure (service unavailable). */
export function scriptedFetch(routes: Record<string, () => Response | Promise<Response>>, calls: { url: string; init?: RequestInit }[] = []): typeof fetch {
  return (async (input: string | URL, init?: RequestInit) => {
    const url = String(input)
    calls.push({ url, init })
    const key = `${init?.method ?? 'GET'} ${url}`
    const r = routes[key]
    if (!r) throw new TypeError('fetch failed')
    return r()
  }) as typeof fetch
}

export const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
