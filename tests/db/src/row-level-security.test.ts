import { beforeAll, describe, expect, it } from "vitest";
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { manifest } from "@saas/db/manifest";

// Supabase's Data API (PostgREST) serves the `public` schema to anyone holding
// the project's anon key. Migration 030 enables row-level security, with no
// policy, on every table there: `anon` and `authenticated` get nothing, and the
// app — which owns the tables — keeps everything. These run every migration
// db-migrate applies, in the manifest's order, on a real Postgres in process
// (PGlite: Postgres compiled to WASM), and read the catalog it leaves.
const migrationsDir = path.resolve(__dirname, "../../../packages/db/src/migrations");
const sqlOf = (rel: string) => readFileSync(path.join(migrationsDir, rel), "utf8");

async function migrated(): Promise<PGlite> {
  const db = new PGlite();
  for (const entry of manifest.migrations) {
    await db.exec(sqlOf(entry.path));
  }
  return db;
}

type Rel = { relname: string; relrowsecurity: boolean; relforcerowsecurity: boolean };
const PUBLIC_TABLES = `
  select c.relname, c.relrowsecurity, c.relforcerowsecurity
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
   order by c.relname`;

describe("row-level security on public (after every migration)", () => {
  let db: PGlite;
  beforeAll(async () => {
    db = await migrated();
  }, 60_000);

  it("leaves no table in public without row-level security", async () => {
    const { rows } = await db.query<Rel>(PUBLIC_TABLES);
    // Not vacuous: the template's tables are all there.
    expect(rows.map((r) => r.relname)).toEqual(
      expect.arrayContaining(["activity_logs", "invitations", "team_members", "teams", "users"]),
    );
    expect(rows.filter((r) => !r.relrowsecurity).map((r) => r.relname)).toEqual([]);
  });

  it("adds no policy and forces none — the owner is never subject to it", async () => {
    const { rows } = await db.query<Rel>(PUBLIC_TABLES);
    expect(rows.filter((r) => r.relforcerowsecurity).map((r) => r.relname)).toEqual([]);
    const policies = await db.query<{ n: number }>(
      "select count(*)::int as n from pg_policies where schemaname = 'public'",
    );
    expect(policies.rows[0]!.n).toBe(0);
  });

  it("gives a role with the Data API's grants nothing, and the owner everything", async () => {
    await db.exec("insert into users (email, password_hash) values ('owner-row@example.invalid', 'h')");
    // What Supabase grants `anon` on public by default — so a refusal below is
    // row-level security's, not a missing grant's.
    await db.exec(`
      create role anon nologin;
      grant usage on schema public to anon;
      grant select, insert, update, delete on all tables in schema public to anon;
      grant usage on all sequences in schema public to anon;`);
    await db.exec("set role anon");
    try {
      const seen = await db.query<{ n: number }>("select count(*)::int as n from users");
      expect(seen.rows[0]!.n).toBe(0);
      await expect(
        db.exec("insert into users (email, password_hash) values ('anon@example.invalid', 'h')"),
      ).rejects.toThrow(/row-level security/);
      await expect(db.query("select value from app_private.secrets")).rejects.toThrow(/permission denied/);
    } finally {
      await db.exec("reset role");
    }
    const owner = await db.query<{ n: number }>("select count(*)::int as n from users");
    expect(owner.rows[0]!.n).toBe(1);
  });
});

describe("migration 030's guard", () => {
  // The guard names `postgres`, the role Hyperdrive connects as, which PGlite
  // cannot take SUPERUSER from. Pointed instead at a role that neither owns the
  // tables nor bypasses RLS, it must refuse — and enable nothing.
  const migration = sqlOf("030_row_level_security/up.sql");
  const aimedAt = (role: string) =>
    migration.replaceAll("rolname = 'postgres'", `rolname = '${role}'`).replaceAll("<> 'postgres'", `<> '${role}'`);

  async function beforeRls(): Promise<PGlite> {
    const db = new PGlite();
    for (const entry of manifest.migrations.filter((m) => m.id < "030")) {
      await db.exec(sqlOf(entry.path));
    }
    return db;
  }

  it("refuses when the app's role would be locked out, enabling nothing", async () => {
    const db = await beforeRls();
    await db.exec("create role app_without_bypass nologin");
    await expect(db.exec(aimedAt("app_without_bypass"))).rejects.toThrow(/would lock the app out/);
    const { rows } = await db.query<Rel>(PUBLIC_TABLES);
    expect(rows.filter((r) => r.relrowsecurity)).toEqual([]);
  }, 60_000);

  it("passes for a role with BYPASSRLS", async () => {
    const db = await beforeRls();
    await db.exec("create role app_with_bypass nologin bypassrls");
    await db.exec(aimedAt("app_with_bypass"));
    const { rows } = await db.query<Rel>(PUBLIC_TABLES);
    expect(rows.every((r) => r.relrowsecurity)).toBe(true);
  }, 60_000);
});
