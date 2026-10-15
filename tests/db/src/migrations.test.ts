import { describe, expect, it } from "vitest";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { manifest } from "@saas/db/manifest";
import { buildPlan, runMigrations } from "@saas/db/runner";

const migrationsDir = path.resolve(__dirname, "../../../packages/db/src/migrations");
const drizzleDir = path.resolve(__dirname, "../../../apps/web/lib/db/migrations");

// db-migrate applies packages/db's copy to stage and prod; drizzle-kit applies
// apps/web's to a local database. They must be the same statements.
const DRIZZLE_TWIN: Record<string, string> = {
  "010_saas_starter_schema": "0000_soft_the_anarchist.sql",
  "020_app_secrets": "0001_app_secrets.sql",
  "030_row_level_security": "0002_row_level_security.sql",
};

function statements(sql: string): string[] {
  return sql
    .split("\n")
    .filter((line) => !line.trim().startsWith("--"))
    .join("\n")
    .split(";")
    .map((s) => s.replace(/\s+/g, " ").trim())
    .filter(Boolean);
}

describe("the migration manifest (packages/db)", () => {
  it("starts with the control migration and names every file with its checksum", () => {
    expect(manifest.migrations[0]?.id).toBe("000_control_baseline");
    for (const entry of manifest.migrations) {
      const file = readFileSync(path.join(migrationsDir, entry.path));
      expect(createHash("sha256").update(file).digest("hex"), entry.id).toBe(entry.checksum);
    }
  });

  it("plans every migration as pending offline", async () => {
    const result = await runMigrations(manifest, { mode: "plan", migrationsDir, adapter: null });
    expect(result.failed).toBeNull();
    expect(result.applied).toEqual(manifest.migrations.map((m) => m.id));
  });

  it("gives every app migration a drizzle-kit twin with the same statements", () => {
    const app = manifest.migrations.filter((m) => m.context === "app");
    expect(app.map((m) => m.id)).toEqual(Object.keys(DRIZZLE_TWIN));
    for (const entry of app) {
      const ours = readFileSync(path.join(migrationsDir, entry.path), "utf8");
      const twin = readFileSync(path.join(drizzleDir, DRIZZLE_TWIN[entry.id]!), "utf8");
      expect(statements(twin), entry.id).toEqual(statements(ours));
    }
  });

  it("generates the session key in the database, idempotently", () => {
    const sql = readFileSync(path.join(migrationsDir, "020_app_secrets/up.sql"), "utf8");
    expect(sql).toMatch(/CREATE SCHEMA IF NOT EXISTS app_private/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS app_private\.secrets/);
    expect(sql).toMatch(/'auth_secret'[\s\S]*gen_random_uuid\(\)[\s\S]*ON CONFLICT \(name\) DO NOTHING/);
  });

  it("skips what the database already recorded", () => {
    const applied = new Map([[manifest.migrations[0]!.id, manifest.migrations[0]!.checksum]]);
    const plan = buildPlan(manifest, applied, migrationsDir);
    expect(plan.alreadyApplied).toEqual([manifest.migrations[0]!.id]);
    expect(plan.pending.map((m) => m.id)).toEqual(manifest.migrations.slice(1).map((m) => m.id));
    expect(plan.checksumMismatches).toEqual([]);
  });
});
