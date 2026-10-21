# saas-starter — design

## 1. What the template is

Next.js App Router. A marketing page (`/`, with the animated terminal), a
pricing page that lists the account's Stripe products and prices and starts
Checkout, email + password sign-up and sign-in (bcrypt hash, HS256 JWT from
`jose` in an httpOnly `session` cookie), `middleware.ts` that guards
`/dashboard*` and re-signs the cookie for another day on every GET, server
actions wrapped by `validatedAction` / `validatedActionWithUser` / `withTeam`
(zod), a dashboard (team members and invitations, account, activity log,
password and account deletion), Stripe Checkout, the Customer Portal and a
webhook that keeps the team's subscription in step. Data lives in Postgres
through Drizzle: `users`, `teams` (with the Stripe ids), `team_members`,
`activity_logs`, `invitations`; drizzle-kit generates the SQL under
`lib/db/migrations`, `lib/db/seed.ts` creates the test user, team and the two
Stripe products. shadcn/ui, Tailwind 4, SWR with server-provided fallbacks.
Next 15.6 canary with `experimental.ppr`.

## 2. The mapping (Vercel → Cloudflare + Supabase)

| Vercel primitive the template uses | Here |
|---|---|
| Next.js hosting (SSR, route handlers, server actions) | Cloudflare Workers + Static Assets; the Worker is `@opennextjs/cloudflare`'s output, assets bound as `ASSETS` |
| `middleware.ts` on the edge | `proxy.ts` — Next 16's name for the same file; OpenNext bundles it as Node.js middleware inside the same Worker. The logic (cookie check, jose refresh, redirect to `/sign-in`) is unchanged |
| Postgres from the marketplace, reached by `postgres(process.env.POSTGRES_URL)` at module scope | The Supabase project's Postgres reached through Cloudflare Hyperdrive: the Worker's `HYPERDRIVE` binding hands out a connection string, and `lib/db/drizzle.ts` builds a `postgres` client + Drizzle **per request** in `getDb()`. Without a Cloudflare context (`next dev` before the bindings are up, the seed, drizzle-kit, tests) it falls back to `POSTGRES_URL`, as upstream |
| `drizzle-kit migrate` against `POSTGRES_URL` | Orun's `db-migrate` component applies `packages/db/src/migrations` — the template's drizzle-kit SQL, verbatim, listed in a checksummed manifest — through Supabase's Management API, per environment, before the Worker deploys. drizzle-kit (`pnpm db:generate`, `db:migrate`, `db:studio`) stays for local development |
| Project env vars set in the Vercel dashboard | `BASE_URL` is a wrangler var rendered per environment (the Worker's own origin; read on the server only). `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` are Worker secrets the owner adds when ready (`.dev.vars` locally); `AUTH_SECRET` likewise, optional — the database generates the session key otherwise. `POSTGRES_URL` is local-only (`.env`) |
| The Stripe SDK over Node's `http` | `Stripe.createFetchHttpClient()`; the webhook verifies its signature with `constructEventAsync` over `Stripe.createSubtleCryptoProvider()` |
| A database created by hand | `infra/terraform/supabase` (Lumen's root): one project per environment, credentials published as orun secrets. `infra/terraform/cloudflare-hyperdrive`: one Hyperdrive config per environment pointed at that database, its id published as a wiring document |
| Deploy on push | Orun: `apps/web/component.yaml` (`cloudflare-workers-assets-turbo`) deploys `saas-starter-web-{stage,prod}` on merge to `main`, after `cloudflare-hyperdrive` and `db-migrate` |

## 3. A request, through Hyperdrive, to Postgres

```
browser ──HTTPS──► saas-starter-web-<env>   (one Worker: proxy + pages + actions + route handlers)
                     │
                     │  proxy.ts        session cookie present? valid? → re-signed (jose) or 307 /sign-in
                     │  page / action   const db = await getDb()
                     │                    ├─ getCloudflareContext().env.HYPERDRIVE.connectionString
                     │                    ├─ postgres(cs, { max: 5, fetch_types: false, prepare: false })
                     │                    └─ drizzle(client, { schema })
                     ▼
            Hyperdrive config  stg-/prod-saas-starter-<env>   (edge-side pooling, TLS to the origin)
                     ▼
            Supabase Postgres  db.<project_ref>.supabase.co:5432
                     ▲
            db-migrate  ── packages/db/src/migrations/{000_control,010_saas_starter_schema,020_app_secrets,030_row_level_security}/up.sql
                           through the Management API, before the Worker deploys

Stripe ──POST /api/stripe/webhook──► Worker: constructEventAsync (SubtleCrypto) → handleSubscriptionChange → getDb() → teams
Stripe ◄── Checkout / Customer Portal sessions with success/cancel/return URLs built from BASE_URL
```

Why per request: the Workers runtime refuses to reuse a socket opened in one
request from another ("Cannot perform I/O on behalf of a different request").
Lumen tried a module-scoped pool, broke membership and billing on stage, and
reverted (`packages/db/src/hyperdrive/executor.ts`). Hyperdrive is the pool;
the Worker's job is to open few connections (`max: 5`), skip the `pg_types`
round trip and send plain statements.

## 4. The env and secret flow

```
infra/terraform/supabase ──apply──► orun secrets (project/<env> rung)
   SUPABASE_PROJECT_REF, SUPABASE_DB_PASSWORD, SUPABASE_DB_URL
        │
        ├──► infra/terraform/cloudflare-hyperdrive (TF_VAR_supabase_project_ref, TF_VAR_supabase_db_password)
        │       ──apply──► WIRING_CLOUDFLARE_HYPERDRIVE = {hyperdrive_id, hyperdrive_name}
        │                        │
        │                        └──► apps/web component secretEnv WIRING_CLOUDFLARE_HYPERDRIVE_<ENV>
        │                               → tooling/wire/live.mjs → wrangler.jsonc  hyperdrive[0].id
        │
        └──► infra/db-migrate (SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF, SUPABASE_DB_PASSWORD, SUPABASE_DB_URL)
                ──apply──► the schema, and app_private.secrets' auth_secret (the session key)

Worker secrets (not from any root — Stripe is the product's account; all optional):
   STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET   wrangler secret put … --name saas-starter-web-<env>
                                              (unset: checkout says Stripe is not connected)
   AUTH_SECRET                                (unset: the session key is the database's own)
Worker var (wrangler.jsonc, per environment):
   BASE_URL = https://saas-starter-web-<env>.<subdomain>.workers.dev
```

`wrangler.template.jsonc` carries the `@@wiring(cloudflare-hyperdrive/__ENV__:hyperdrive_id)@@`
token and a `localConnectionString` for `wrangler dev` / `next dev`
(`postgres://postgres:postgres@localhost:54322/postgres` — the Supabase CLI's
default, and the Docker Postgres upstream's `pnpm db:setup` creates). The
`pnpm run wire:fixture` renders it from `wiring.fixture.json` into the
COMMITTED `wrangler.jsonc` — the composition checks that file exists before
the build, in a fresh checkout — which `wrangler dev`, `next dev` and the dev
verify lane use; the stage and prod lanes re-render it from the live document
for `$ORUN_ENVIRONMENT` before they build (SA5; it was git-ignored before).

`BASE_URL` is a var, not a secret, and not wired: no root knows the account's
workers.dev subdomain. The template carries the same subdomain as
`component.yaml` and `intent.yaml` (`your-workers-subdomain` here; a
bootstrap writes the product's own, which a console build reads from the
workspace's Cloudflare connection — SA-8), or a custom domain.

On a push to main the four components converge in one run, per environment,
in the order the arrows above imply — `supabase → cloudflare-hyperdrive →
db-migrate → web` — because each component that reads another's output
declares `dependsOn` on it with `mode: enforced` (advisory on a pull request).
A job resolves its secrets when it starts, so what an apply published is
there for the next.

## 5. The repository

```
apps/web                      the template (app/, components/, lib/, proxy.ts) + the Workers build
  lib/db/drizzle.ts           getDb(): postgres + drizzle per request over HYPERDRIVE, POSTGRES_URL fallback
  component.yaml              render wrangler from the Hyperdrive wiring, build with turbo, deploy, smoke /
  wrangler.template.jsonc     worker name, nodejs_compat, ASSETS, the HYPERDRIVE binding, BASE_URL
  wiring.fixture.json         offline values for the verify lane
  .dev.vars.example           the Worker secrets, for wrangler dev
  open-next.config.ts         static-assets incremental cache (nothing revalidates for real)
packages/db                   @saas/db: the migrations (000_control, 010_saas_starter_schema, 020_app_secrets, 030_row_level_security — SA5) + Lumen's runner
infra/db-migrate              applies them per environment through the Management API (after supabase)
infra/terraform/supabase      the Supabase project per environment (Lumen's root; since SA5 it no longer reads the API keys)
infra/terraform/cloudflare-hyperdrive   the Hyperdrive config per environment, fronting that database
tests/web                     vitest: session sign/verify, bcrypt, the proxy's decisions, the webhook route (mocked Stripe)
tests/db                      vitest: manifest checksums, offline plan, row-level security on every table (PGlite)
```

## 6. Alternatives rejected

**Supabase PostgREST (`@supabase/supabase-js`) instead of Drizzle.** The
template's data access is SQL: Drizzle's query builder with joins
(`signIn`, `getUserWithTeam`, `inviteTeamMember`), the relational query API
(`getTeamForUser`), raw fragments (`sql\`CONCAT(email, '-', id, '-deleted')\``
in the soft delete), `.returning()`. Re-expressing every query and action
over PostgREST is a rewrite, loses drizzle-kit and the seed, and still leaves
the schema to be applied by something. The port's rule is that the code stays
the code; Hyperdrive gives the Worker the socket the code already expects.

**Cloudflare D1 instead of Postgres.** The schema is Postgres: `serial`
keys, `varchar(n)`, `timestamp DEFAULT now()`, named unique constraints on
the Stripe customer and subscription ids, foreign keys added in `DO $$ …
duplicate_object` blocks. drizzle's `pg-core` schema and `postgres-js` driver
would become `sqlite-core` and the D1 driver, the migration regenerated, the
Stripe-facing columns and the activity timestamps re-typed. That is a
different database, not a port — and the Supabase port is what the Lumen
baseline is for.

**A module-level pool.** See §3: the runtime forbids it.

## 7. Out of scope

A custom domain; sending the invitation email (upstream's TODO); creating
the Stripe products and prices in a live account (the seed creates them
against the account's test mode; the pricing page falls back to its defaults
until they exist); registering the production webhook endpoint in Stripe's
dashboard (the README says where); the Supabase CLI's full local stack (any
Postgres on `localhost:54322` will do).
