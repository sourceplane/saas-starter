import { sql } from 'drizzle-orm';
import { getDb } from '@/lib/db/drizzle';

// Not upstream's: the deploy's smoke check and the bootstrap's probe read
// this. A home page that renders proves the Worker deployed; this proves what
// the home page never touches — the HYPERDRIVE binding names a real config,
// Hyperdrive reaches the Supabase database, and db-migrate applied the schema
// (the template's tables and the session key the app signs cookies with).
export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const db = await getDb();
    const [row] = await db.execute<{
      users: string | null;
      secrets: string | null;
    }>(
      sql`select to_regclass('public.users')::text as users,
                 to_regclass('app_private.secrets')::text as secrets`
    );
    const ok = Boolean(row?.users && row?.secrets);
    return Response.json(
      { ok, database: 'reachable', schema: ok ? 'migrated' : 'missing' },
      { status: ok ? 200 : 503, headers: { 'cache-control': 'no-store' } }
    );
  } catch (error) {
    console.error('health: database check failed', error);
    return Response.json(
      { ok: false, database: 'unreachable' },
      { status: 503, headers: { 'cache-control': 'no-store' } }
    );
  }
}
