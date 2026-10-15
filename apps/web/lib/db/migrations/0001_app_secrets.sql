-- The same SQL as packages/db/src/migrations/020_app_secrets/up.sql, which is
-- what db-migrate applies to stage and prod; this copy is for drizzle-kit
-- (`pnpm db:migrate`) against a local database. lib/auth/secret.ts reads it.
CREATE SCHEMA IF NOT EXISTS app_private;
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS app_private.secrets (
  name       TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
--> statement-breakpoint
INSERT INTO app_private.secrets (name, value)
VALUES ('auth_secret', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
ON CONFLICT (name) DO NOTHING;
