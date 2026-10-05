-- RENDER_EDIT_PLAN support: BLOCKED reason rename + runner-side reconciliation state. Idempotent.
-- LEASE_EXPIRED_RECONCILE_REQUIRED (0002) becomes LOCAL_SIDE_EFFECT_UNKNOWN: a local file may have been written.

ALTER TABLE artist_os_mac_jobs DROP CONSTRAINT IF EXISTS artist_os_mac_jobs_blocked_reason_check;
UPDATE artist_os_mac_jobs SET blocked_reason = 'LOCAL_SIDE_EFFECT_UNKNOWN' WHERE blocked_reason = 'LEASE_EXPIRED_RECONCILE_REQUIRED';
ALTER TABLE artist_os_mac_jobs ADD CONSTRAINT artist_os_mac_jobs_blocked_reason_check
  CHECK (blocked_reason IS NULL OR blocked_reason IN ('LOCAL_SIDE_EFFECT_UNKNOWN','LEASE_EXPIRED_OUTCOME_UNKNOWN'));

-- {state: requested|in_progress|ambiguous|resolved, requestedAt, updatedAt, outcome?, evidence?}
ALTER TABLE artist_os_mac_jobs ADD COLUMN IF NOT EXISTS reconcile jsonb;
ALTER TABLE artist_os_mac_jobs DROP CONSTRAINT IF EXISTS artist_os_mac_jobs_reconcile_state_check;
ALTER TABLE artist_os_mac_jobs ADD CONSTRAINT artist_os_mac_jobs_reconcile_state_check
  CHECK (reconcile IS NULL OR reconcile->>'state' IN ('requested','in_progress','ambiguous','resolved'));
CREATE INDEX IF NOT EXISTS artist_os_mac_jobs_reconcile_idx ON artist_os_mac_jobs (runner_id) WHERE status = 'BLOCKED';

INSERT INTO artist_os_schema_migrations (version, name) VALUES (4, 'render_reconcile') ON CONFLICT (version) DO NOTHING;
