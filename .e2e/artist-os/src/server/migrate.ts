import pg from 'pg'
import { applyMigrations } from '../ledger/postgres-storage.js'

/** npm run db:migrate — applies Artist OS's own idempotent migrations to ARTIST_OS_DATABASE_URL. */
const url = process.env.ARTIST_OS_DATABASE_URL
if (!url) {
  console.error('ARTIST_OS_DATABASE_URL is not set (this must be Artist OS\'s own database, not a specialist\'s).')
  process.exit(2)
}
const pool = new pg.Pool({ connectionString: url })
applyMigrations(pool)
  .then(() => console.log('artist-os migrations applied'))
  .catch((e: Error) => {
    console.error('migration failed:', e.message)
    process.exitCode = 1
  })
  .finally(() => pool.end())
