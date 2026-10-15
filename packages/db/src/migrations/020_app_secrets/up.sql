-- Values the app needs that no platform brokers and no owner has set yet,
-- generated inside the environment's own database (lib/auth/secret.ts reads
-- them). Kept out of `public`, which Supabase's Data API exposes.
--
-- Idempotent, as every migration here must be: the Supabase Management API
-- adapter sends each statement in autocommit mode.

CREATE SCHEMA IF NOT EXISTS app_private;

CREATE TABLE IF NOT EXISTS app_private.secrets (
  name       TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The session-signing key a fresh environment starts with: 64 hex characters
-- from two v4 UUIDs, which gen_random_uuid() draws from pg_strong_random. An
-- AUTH_SECRET Worker secret, once an owner sets one, takes precedence.
INSERT INTO app_private.secrets (name, value)
VALUES ('auth_secret', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
ON CONFLICT (name) DO NOTHING;
