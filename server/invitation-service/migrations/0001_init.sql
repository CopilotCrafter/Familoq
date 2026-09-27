-- Familoq invitation service. Stores NO financial data:
-- only hashed invitation codes, hashed Apple user IDs, statuses and dates.

CREATE TABLE IF NOT EXISTS invitations (
  id            TEXT PRIMARY KEY,
  code_hash     TEXT NOT NULL UNIQUE,      -- SHA-256 of the normalised code
  hint          TEXT NOT NULL,             -- last 4 characters, for the admin list
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'used', 'revoked')),
  note          TEXT,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL,
  redeemed_by   TEXT,                      -- users.id
  redeemed_at   INTEGER
);

CREATE TABLE IF NOT EXISTS users (
  id              TEXT PRIMARY KEY,
  apple_sub_hash  TEXT NOT NULL UNIQUE,    -- HMAC of the Apple user identifier
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  invitation_id   TEXT,
  created_at      INTEGER NOT NULL,
  last_seen_at    INTEGER
);

CREATE TABLE IF NOT EXISTS invitation_requests (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  contact     TEXT NOT NULL,
  message     TEXT,
  status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'done')),
  created_at  INTEGER NOT NULL
);

-- Simple rate limiting (failed redeem attempts, invitation requests).
CREATE TABLE IF NOT EXISTS rate_events (
  kind        TEXT NOT NULL,
  key_hash    TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS rate_events_lookup ON rate_events (kind, key_hash, created_at);
