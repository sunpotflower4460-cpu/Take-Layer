-- Artist OS domain persistence: Goal, Release, IdentityLink, AssetRef, OperationTrace. Idempotent.
-- Each table keeps the validated record as jsonb (schemaVersion inside) plus the columns needed for constraints and lookup,
-- so a schema evolution does not need a table rewrite and the DB can still enforce the rules that matter.

CREATE TABLE IF NOT EXISTS artist_os_goals (
  goal_id       text PRIMARY KEY,
  workspace_ref text NOT NULL,
  status        text NOT NULL,
  priority      text NOT NULL,
  data          jsonb NOT NULL,
  updated_at    timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS artist_os_goals_ws_idx ON artist_os_goals (workspace_ref, status);

CREATE TABLE IF NOT EXISTS artist_os_releases (
  release_id    text PRIMARY KEY,
  workspace_ref text NOT NULL,
  status        text NOT NULL CHECK (status IN ('planning','in_production','scheduled','released','archived')),
  data          jsonb NOT NULL,
  updated_at    timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS artist_os_releases_ws_idx ON artist_os_releases (workspace_ref, status);

-- Explicit links between Artist OS entities and specialist-owned ids. NEVER replaces a specialist id.
CREATE TABLE IF NOT EXISTS artist_os_identity_links (
  link_id         text PRIMARY KEY,
  artist_os_key   text NOT NULL,   -- system:entityType:entityId of the Artist OS entity (e.g. a Release)
  target_key      text NOT NULL,   -- system:entityType:entityId of the specialist entity
  target_system   text NOT NULL,
  target_type     text NOT NULL,
  status          text NOT NULL CHECK (status IN ('proposed','confirmed','rejected','revoked')),
  evidence        text NOT NULL,
  data            jsonb NOT NULL,
  updated_at      timestamptz NOT NULL
);
-- The graph's rules, enforced by the database as well:
--   one CONFIRMED target per (entity, target system, target type)
CREATE UNIQUE INDEX IF NOT EXISTS artist_os_identity_one_confirmed_slot ON artist_os_identity_links (artist_os_key, target_system, target_type) WHERE status = 'confirmed';
--   no duplicate live link for the same pair
CREATE UNIQUE INDEX IF NOT EXISTS artist_os_identity_one_live_pair ON artist_os_identity_links (artist_os_key, target_key) WHERE status IN ('proposed','confirmed');
CREATE INDEX IF NOT EXISTS artist_os_identity_target_idx ON artist_os_identity_links (target_key) WHERE status = 'confirmed';

-- Cross-domain asset REFERENCES (never bytes). A runner-local locationId is an opaque id, never a path.
CREATE TABLE IF NOT EXISTS artist_os_asset_refs (
  asset_ref     text PRIMARY KEY,
  owner_system  text NOT NULL,
  kind          text NOT NULL,
  location_type text NOT NULL,
  runner_id     text,
  content_hash  text,
  data          jsonb NOT NULL,
  created_at    timestamptz NOT NULL,
  CONSTRAINT runner_local_has_runner CHECK (location_type <> 'runner-local' OR runner_id IS NOT NULL),
  CONSTRAINT no_filesystem_path CHECK (data->>'locationId' !~ '^(/|[A-Za-z]:\\|~)')
);
CREATE INDEX IF NOT EXISTS artist_os_asset_refs_hash_idx ON artist_os_asset_refs (content_hash) WHERE content_hash IS NOT NULL;

-- Operation trace: "why did this happen?" Append-only. Decision summaries, never model reasoning.
CREATE TABLE IF NOT EXISTS artist_os_trace_events (
  event_id       text PRIMARY KEY,
  trace_id       text NOT NULL,
  correlation_id text NOT NULL,
  causation_id   text,
  event_type     text NOT NULL,
  producer       text NOT NULL,
  workspace_ref  text NOT NULL,
  occurred_at    timestamptz NOT NULL,
  data           jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS artist_os_trace_trace_idx ON artist_os_trace_events (trace_id, occurred_at);
CREATE OR REPLACE FUNCTION artist_os_trace_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'artist_os_trace_events is append-only';
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS artist_os_trace_no_update ON artist_os_trace_events;
CREATE TRIGGER artist_os_trace_no_update BEFORE UPDATE OR DELETE ON artist_os_trace_events FOR EACH ROW EXECUTE FUNCTION artist_os_trace_immutable();

INSERT INTO artist_os_schema_migrations (version, name) VALUES (3, 'domain') ON CONFLICT (version) DO NOTHING;
