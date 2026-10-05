-- Artist OS durable Mac job queue. Artist OS's OWN database. Idempotent.
-- Responsibilities are separate from the Action Ledger tables (0001): this is work distribution, that is write ownership.

CREATE TABLE IF NOT EXISTS artist_os_mac_runners (
  runner_id           text PRIMARY KEY,
  architecture        text NOT NULL,
  status              text NOT NULL CHECK (status IN ('idle','busy','draining')),
  capabilities        jsonb NOT NULL,          -- what the runner REPORTED it can do (booleans); never inferred
  supported_job_types text[] NOT NULL,         -- job types with a real handler on that runner
  version             text,
  first_seen_at       timestamptz NOT NULL,
  last_seen_at        timestamptz NOT NULL     -- the heartbeat
);

-- Append-only history of capability changes ("what could this runner do, and since when").
CREATE TABLE IF NOT EXISTS artist_os_mac_runner_snapshots (
  id                  bigserial PRIMARY KEY,
  runner_id           text NOT NULL,
  at                  timestamptz NOT NULL,
  capabilities        jsonb NOT NULL,
  supported_job_types text[] NOT NULL
);
CREATE INDEX IF NOT EXISTS artist_os_mac_runner_snapshots_idx ON artist_os_mac_runner_snapshots (runner_id, id DESC);

CREATE TABLE IF NOT EXISTS artist_os_mac_jobs (
  job_id            text PRIMARY KEY,
  workspace_ref     text NOT NULL,
  job_type          text NOT NULL,
  status            text NOT NULL CHECK (status IN ('QUEUED','CLAIMED','PREPARING','RUNNING','VERIFYING','COMPLETED','FAILED','BLOCKED','CANCELLED')),
  priority          integer NOT NULL DEFAULT 50 CHECK (priority BETWEEN 0 AND 100),
  subject_refs      jsonb NOT NULL DEFAULT '[]',
  -- Opaque asset ids + hashes + metadata only. A runner-local locationId is never a filesystem path
  -- (AssetRef validation rejects those before they reach this table).
  input_asset_refs  jsonb NOT NULL DEFAULT '[]',
  parameters        jsonb NOT NULL DEFAULT '{}',
  progress          real NOT NULL DEFAULT 0,
  current_stage     text,
  runner_id         text,
  attempt           integer NOT NULL DEFAULT 0,
  max_attempts      integer NOT NULL DEFAULT 3,
  created_at        timestamptz NOT NULL,
  expires_at        timestamptz,
  claimed_at        timestamptz,
  heartbeat_at      timestamptz,
  lease_expires_at  timestamptz,
  completed_at      timestamptz,
  error             jsonb,
  blocked_reason    text CHECK (blocked_reason IS NULL OR blocked_reason IN ('LEASE_EXPIRED_RECONCILE_REQUIRED','LEASE_EXPIRED_OUTCOME_UNKNOWN')),
  idempotency_key   text,
  trace_id          text,
  causation_id      text,
  result_artifacts  jsonb NOT NULL DEFAULT '[]',   -- small validated inline artifacts (measurements, never media)
  updated_at        timestamptz NOT NULL,
  CONSTRAINT in_flight_has_lease CHECK (status NOT IN ('CLAIMED','PREPARING','RUNNING','VERIFYING') OR (runner_id IS NOT NULL AND lease_expires_at IS NOT NULL)),
  CONSTRAINT blocked_has_reason CHECK (status <> 'BLOCKED' OR blocked_reason IS NOT NULL),
  CONSTRAINT terminal_has_completed_at CHECK (status NOT IN ('COMPLETED','FAILED','CANCELLED') OR completed_at IS NOT NULL),
  CONSTRAINT failed_has_error CHECK (status <> 'FAILED' OR error IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS artist_os_mac_jobs_idem_idx ON artist_os_mac_jobs (workspace_ref, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS artist_os_mac_jobs_claim_idx ON artist_os_mac_jobs (priority DESC, created_at) WHERE status = 'QUEUED';
CREATE INDEX IF NOT EXISTS artist_os_mac_jobs_lease_idx ON artist_os_mac_jobs (lease_expires_at) WHERE status IN ('CLAIMED','PREPARING','RUNNING','VERIFYING');
CREATE INDEX IF NOT EXISTS artist_os_mac_jobs_trace_idx ON artist_os_mac_jobs (trace_id) WHERE trace_id IS NOT NULL;

-- One row per claim. A job that is re-claimed after a lease expiry keeps its history.
CREATE TABLE IF NOT EXISTS artist_os_mac_job_attempts (
  job_id      text NOT NULL REFERENCES artist_os_mac_jobs(job_id) ON DELETE CASCADE,
  attempt     integer NOT NULL,
  runner_id   text NOT NULL,
  claimed_at  timestamptz NOT NULL,
  ended_at    timestamptz,
  end_reason  text CHECK (end_reason IS NULL OR end_reason IN ('completed','failed','lease_expired','cancelled','blocked')),
  PRIMARY KEY (job_id, attempt)
);

-- Result asset references (runner-local ids + hashes; bytes stay on the runner).
CREATE TABLE IF NOT EXISTS artist_os_mac_job_artifact_refs (
  job_id     text NOT NULL REFERENCES artist_os_mac_jobs(job_id) ON DELETE CASCADE,
  ref_index  integer NOT NULL,
  asset_ref  jsonb NOT NULL,
  PRIMARY KEY (job_id, ref_index)
);

INSERT INTO artist_os_schema_migrations (version, name) VALUES (2, 'mac_jobs') ON CONFLICT (version) DO NOTHING;
