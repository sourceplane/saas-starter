import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';
import dotenv from 'dotenv';
import { getCloudflareContext } from '@opennextjs/cloudflare';

dotenv.config();

// The one departure from upstream, forced by the Workers runtime. Upstream
// exports a module-level `client` and `db` over POSTGRES_URL; on Cloudflare
// the connection string is the Hyperdrive binding's, and a `postgres` client
// opened in one request cannot be reused by another ("Cannot perform I/O on
// behalf of a different request"), so every caller builds its own:
//
//   const db = await getDb();
//
// Without a Cloudflare context — `next dev` before the bindings are up, the
// seed and setup scripts, drizzle-kit, tests — POSTGRES_URL is the connection
// string, exactly as upstream.
async function connectionString(): Promise<string> {
  try {
    const { env } = await getCloudflareContext({ async: true });
    const hyperdrive = (env as { HYPERDRIVE?: { connectionString: string } })
      .HYPERDRIVE;
    if (hyperdrive?.connectionString) {
      return hyperdrive.connectionString;
    }
  } catch {
    // Not running under OpenNext (locally or in a script): fall through.
  }

  if (!process.env.POSTGRES_URL) {
    throw new Error('POSTGRES_URL environment variable is not set');
  }
  return process.env.POSTGRES_URL;
}

export async function getDb() {
  // Hyperdrive pools on its side; a Worker request holds few connections,
  // skips the pg_types round trip and sends plain (unprepared) statements.
  const client = postgres(await connectionString(), {
    max: 5,
    fetch_types: false,
    prepare: false
  });
  return drizzle(client, { schema });
}

export type Database = Awaited<ReturnType<typeof getDb>>;
