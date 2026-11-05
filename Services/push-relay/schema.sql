-- One row per app install that can be reached. Only hashes of its two secrets are kept:
-- `secret` lets the app update or remove its row, `send_key` lets its gateway push to it.
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  token TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  secret_hash TEXT NOT NULL,
  send_key_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
