-- The same SQL as packages/db/src/migrations/030_row_level_security/up.sql
-- (which says why), for drizzle-kit (`pnpm db:migrate`) against a local
-- database. The ALTERs are drizzle-kit's own, from schema.ts's
-- `.enableRLS()`; the guard ahead of them was added by hand.
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
--> statement-breakpoint
ALTER TABLE "activity_logs" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE "invitations" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE "team_members" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE "teams" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE "users" ENABLE ROW LEVEL SECURITY;
