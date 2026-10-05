-- Artist OS action ledger. Artist OS's OWN database: never point this at a specialist's DB.
-- Idempotent: safe to run repeatedly.

CREATE TABLE IF NOT EXISTS artist_os_schema_migrations (
  version     integer PRIMARY KEY,
  name        text NOT NULL,
  applied_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS artist_os_action_ledger (
  -- CrossSystemActionKey: <platform>:<operation>:<native external event id>
  action_key        text PRIMARY KEY,
  owner_system      text NOT NULL,
  state             text NOT NULL CHECK (state IN ('RESERVED','EXECUTING','SUCCEEDED','FAILED_SAFE_TO_RETRY','OUTCOME_UNKNOWN','RECONCILED')),
  attempt           integer NOT NULL CHECK (attempt >= 1),
  reservation_token text NOT NULL,
  reserved_at       timestamptz NOT NULL,
  lease_expires_at  timestamptz NOT NULL,
  executing_at      timestamptz,
  completed_at      timestamptz,
  outcome_ref       text,
  failure_code      text,
  unknown_reason    text,
  reconciliation    jsonb,
  updated_at        timestamptz NOT NULL,
  version           integer NOT NULL CHECK (version >= 1),
  -- A reconciled row must say how; an unknown row must say why.
  CONSTRAINT reconciled_has_resolution CHECK (state <> 'RECONCILED' OR reconciliation IS NOT NULL),
  CONSTRAINT unknown_has_reason CHECK (state <> 'OUTCOME_UNKNOWN' OR unknown_reason IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS artist_os_action_ledger_state_idx ON artist_os_action_ledger (state, updated_at DESC);

-- Append-only audit trail of every transition and every refusal.
CREATE TABLE IF NOT EXISTS artist_os_action_events (
  id          bigserial PRIMARY KEY,
  action_key  text NOT NULL,
  at          timestamptz NOT NULL,
  kind        text NOT NULL,
  actor       text NOT NULL,
  from_state  text NOT NULL,
  to_state    text NOT NULL,
  detail      text
);
CREATE INDEX IF NOT EXISTS artist_os_action_events_key_idx ON artist_os_action_events (action_key, id);

-- The audit trail must stay append-only.
CREATE OR REPLACE FUNCTION artist_os_action_events_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'artist_os_action_events is append-only';
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS artist_os_action_events_no_update ON artist_os_action_events;
CREATE TRIGGER artist_os_action_events_no_update BEFORE UPDATE OR DELETE ON artist_os_action_events
  FOR EACH ROW EXECUTE FUNCTION artist_os_action_events_immutable();

INSERT INTO artist_os_schema_migrations (version, name) VALUES (1, 'action_ledger') ON CONFLICT (version) DO NOTHING;
