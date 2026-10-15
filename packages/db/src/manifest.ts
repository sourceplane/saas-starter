import type { MigrationManifest } from "./types.js";

// Every migration the runner applies, in order, with the sha256 of its file.
// `pnpm --filter @saas/db run manifest:check` verifies the checksums;
// `manifest:fix` rewrites them after a migration file changes (only ever
// before that migration has been applied anywhere — an applied migration's
// checksum is immutable).
export const manifest: MigrationManifest = {
  version: 1,
  migrations: [
    {
      id: "000_control_baseline",
      context: "control",
      path: "000_control/up.sql",
      checksum:
        "2a5d7f30684c99e3ff441ca8a2c38038dedd1bab4db4a40e92cd36bb22be297f",
      description:
        "Baseline control migration — creates the migration tracking schema",
    },
    {
      id: "010_saas_starter_schema",
      context: "app",
      path: "010_saas_starter_schema/up.sql",
      checksum:
        "5a710a65173f1c510ebe80d425fbaa0696bdc850f77be850e3bff22e5bcc5ebb",
      description:
        "The template's schema (lib/db/migrations/0000_soft_the_anarchist.sql, drizzle-kit's output, verbatim): users, teams, team_members, activity_logs, invitations and their foreign keys",
    },
  ],
};
