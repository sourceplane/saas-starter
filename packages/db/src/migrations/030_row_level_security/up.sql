-- Row-level security on every table in `public`, and no policies.
--
-- Supabase's Data API (PostgREST) serves `public` to anyone holding the
-- project's anon key, which is public by Supabase's design. Upstream assumed
-- a private Postgres, so its tables — `users` with its password hashes among
-- them — had no RLS, and the Data API would hand them out. With RLS enabled
-- and no policy, `anon` and `authenticated` read and write NOTHING through
-- it. The app is not affected: it connects through Hyperdrive as `postgres`
-- (the cloudflare-hyperdrive root's database_user), which created and owns
-- these tables, and a table's owner is not subject to its RLS unless FORCE is
-- set (it is not). The migration ledgers (`_migrations`, drizzle-kit's
-- `drizzle`) and `app_private` are schemas the Data API does not expose.
--
-- apps/web/lib/db/schema.ts declares `.enableRLS()` on each table, which is
-- how drizzle-kit wrote the ALTERs below (its twin is
-- apps/web/lib/db/migrations/0002_row_level_security.sql); tests/db fails if
-- any table in `public` is left without RLS after the migrations.
--
-- FIRST, the guard. If `postgres` neither owns every table here nor has
-- SUPERUSER or BYPASSRLS, enabling RLS would lock the app out of its own
-- data: stop. The guard changes nothing and runs before the first ALTER, so
-- a refusal enables nothing. Idempotent: ENABLE on an enabled table is a
-- no-op.
DO $$
DECLARE
  app_bypasses boolean;
  not_owned text;
BEGIN
  SELECT rolsuper OR rolbypassrls INTO app_bypasses FROM pg_roles WHERE rolname = 'postgres';
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO not_owned
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
     AND pg_get_userbyid(c.relowner) <> 'postgres';
  IF NOT coalesce(app_bypasses, false) AND not_owned IS NOT NULL THEN
    RAISE EXCEPTION 'row-level security would lock the app out of %: postgres (the role Hyperdrive connects as) neither owns them nor has SUPERUSER or BYPASSRLS', not_owned;
  END IF;
END
$$;

ALTER TABLE "activity_logs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "invitations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "team_members" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "teams" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "users" ENABLE ROW LEVEL SECURITY;
