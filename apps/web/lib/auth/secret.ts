import { sql } from 'drizzle-orm';

// The key that signs the session cookie (lib/auth/session.ts).
//
// Upstream reads AUTH_SECRET, which its setup script writes into .env. A
// deployed Worker has no setup script, so a fresh deployment would start with
// no key and refuse every sign-up until its owner ran `wrangler secret put`.
// The key is therefore the first of these that exists:
//
//   1. AUTH_SECRET — a Worker secret in a deployment, .dev.vars or .env
//      locally. Setting it is how an owner rotates the key: every session
//      signed under the previous one ends.
//   2. the key this environment's database generated for itself. Migration
//      020_app_secrets writes 64 random hex characters into
//      app_private.secrets the first time it runs, so the key is never in a
//      repository, a CI log or a deploy artifact, and stage and prod each have
//      their own. `app_private` is not a schema Supabase's Data API exposes.
//
// The stored key is read once per isolate and kept as a plain string: it does
// not change under a running Worker, and a string (unlike a pending query) is
// safe to share between requests.
let stored: string | undefined;

export async function authSecret(): Promise<string> {
  const configured = process.env.AUTH_SECRET;
  if (configured) {
    return configured;
  }
  if (stored) {
    return stored;
  }
  // Imported here rather than at the top so that a process with AUTH_SECRET
  // set (the tests, local scripts) never loads the database client.
  const { getDb } = await import('@/lib/db/drizzle');
  const db = await getDb();
  const rows = await db.execute<{ value: string }>(
    sql`select value from app_private.secrets where name = 'auth_secret'`
  );
  const value = rows[0]?.value;
  if (!value) {
    throw new Error(
      'No AUTH_SECRET is set and the database holds no auth_secret: apply the migrations (020_app_secrets) or set AUTH_SECRET'
    );
  }
  stored = value;
  return value;
}
