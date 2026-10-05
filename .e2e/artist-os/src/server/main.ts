import { createServer } from 'node:http'
import pg from 'pg'
import { PostgresLedgerStorage } from '../ledger/postgres-storage.js'
import { PostgresMacJobQueue } from '../runner/postgres-queue.js'
import { PostgresDomainStore } from '../store/postgres-domain-store.js'
import { resolveEnvironment } from '../ledger/store-policy.js'
import { Workspace } from '../app/workspace.js'
import { JsonStateFile } from '../store/file-store.js'
import { clientConfigFromEnv, createApp } from './app.js'

/**
 * Local entry point:  node dist/server/main.js
 *   ARTIST_OS_OPERATOR_TOKEN  required for the operator API (else 503)
 *   ARTIST_OS_RUNNER_TOKEN    required for the Runner API (else 503)
 *   ARTIST_OS_STATE_FILE      default ./.artist-os/state.json
 *   ARTIST_OS_<SERVICE>_URL / _TOKEN   per specialist; unset ⇒ that service stays disabled
 * Boots with nothing configured: every specialist and all equipment simply show as not connected.
 */
const env = process.env
const environment = resolveEnvironment(env.ARTIST_OS_ENV)
// The Action Ledger's production store is Artist OS's OWN Postgres (never a specialist's database).
// Without ARTIST_OS_DATABASE_URL the ledger falls back to the dev JSON store, which the Store Policy refuses for
// production write coordination (the ledger API then answers 503 and specialists fail closed).
const pool = env.ARTIST_OS_DATABASE_URL ? new pg.Pool({ connectionString: env.ARTIST_OS_DATABASE_URL, max: 10 }) : undefined
const ws = new Workspace({
  workspaceRef: env.ARTIST_OS_WORKSPACE ?? 'default',
  file: new JsonStateFile(env.ARTIST_OS_STATE_FILE ?? '.artist-os/state.json'),
  ...(pool ? { ledgerStorage: new PostgresLedgerStorage(pool), queue: new PostgresMacJobQueue(pool), domain: new PostgresDomainStore(pool) } : {}),
})
const handle = createApp(ws, {
  operatorToken: env.ARTIST_OS_OPERATOR_TOKEN?.trim() || undefined,
  runnerToken: env.ARTIST_OS_RUNNER_TOKEN?.trim() || undefined,
  specialistConfig: clientConfigFromEnv(env),
  ledgerTokens: { 'my-sns': env.ARTIST_OS_LEDGER_TOKEN_MY_SNS?.trim() || undefined, 'sns-providers': env.ARTIST_OS_LEDGER_TOKEN_SNS_PROVIDERS?.trim() || undefined },
  environment,
  writeCoordinationRequested: env.ARTIST_OS_WRITE_COORDINATION === 'enabled',
  macJobsRequested: env.ARTIST_OS_MAC_JOBS === 'enabled',
})

// Lease maintenance: expired leases are applied by claim()/update() too, but a periodic tick keeps the state honest
// (BLOCKED jobs appear in Today even when no Runner is polling).
setInterval(() => void ws.queue.reclaimExpired().catch(() => undefined), 30_000).unref()

const MAX_BODY = 256_000
createServer((req, res) => {
  const chunks: Buffer[] = []
  let size = 0
  req.on('data', (c: Buffer) => {
    size += c.length
    if (size > MAX_BODY) req.destroy()
    else chunks.push(c)
  })
  req.on('end', () => {
    void (async () => {
      let body: unknown
      try {
        body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : undefined
      } catch {
        res.writeHead(400, { 'content-type': 'application/json' }).end('{"error":"invalid_json"}')
        return
      }
      const headers: Record<string, string | undefined> = {}
      for (const [k, v] of Object.entries(req.headers)) headers[k] = Array.isArray(v) ? v[0] : v
      const out = await handle({ method: req.method ?? 'GET', path: new URL(req.url ?? '/', 'http://x').pathname, query: Object.fromEntries(new URL(req.url ?? '/', 'http://x').searchParams), headers, body }).catch(() => ({ status: 500, body: { error: 'internal' }, contentType: undefined }))
      res
        .writeHead(out.status, { 'content-type': out.contentType ?? 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' })
        .end(typeof out.body === 'string' ? out.body : JSON.stringify(out.body))
    })()
  })
}).listen(Number(env.PORT ?? 8787), env.HOST ?? '127.0.0.1', () => console.log(`artist-os listening on ${env.HOST ?? '127.0.0.1'}:${env.PORT ?? 8787}`))
