# saas-starter — risks and open questions

## SA-A — A `postgres` client per request (ACCEPTED, by design)

Every `getDb()` opens its own client (`max: 5`, `fetch_types: false`,
`prepare: false`) and leaves it to the request's end. Hyperdrive is the
pool — it keeps warm connections to the origin at the edge — so the cost per
request is a short hop to Hyperdrive, not a TLS handshake to Supabase. A
module-level pool is the thing that does not work on Workers (Lumen's
executor comment records the incident); the per-request shape is the
baseline's and is kept.

## SA-B — Env read at module scope (RESOLVED)

`lib/auth/session.ts` derives the JWT key from `AUTH_SECRET`,
`lib/payments/stripe.ts` constructs the client from `STRIPE_SECRET_KEY`, the
webhook route captures `STRIPE_WEBHOOK_SECRET` — all when their module loads.
OpenNext populates `process.env` from the Worker's env (vars and secrets)
before it imports the Next handler on the first request, so the values are
there; verified under `wrangler dev` with `.dev.vars`. The code is kept as
written.

## SA-C — PPR under Next 16 (RESOLVED)

Upstream enables `experimental.ppr` and `experimental.clientSegmentCache` on
a Next 15 canary. Next 16.3.8 hard-errors on the first ("merged into
`cacheComponents`") and does not know the second. `cacheComponents: true`
would make the pricing page's `revalidate = 3600` an error and demand a
Suspense boundary above the root layout's cookie read — template rewrites.
Both keys are dropped; every route renders per request, which is what the
root layout's `getUser()` already forces. Recorded as a departure.

## SA-D — Worker secrets are not set by the deploy (ACCEPTED, documented)

The `cloudflare-workers-assets-turbo` composition has no secrets step (its
parameter schema is closed; `runtimeSecrets` belongs to the plain-Worker
composition). `AUTH_SECRET`, `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET`
are set once per environment with `wrangler secret put … --name
saas-starter-web-<env>`; the README says so. Stripe's keys are the product's
own account, not something a Terraform root could mint.

## SA-E — Migrations through the Management API, autocommit (ACCEPTED)

The runner sends each migration as one query to Supabase's
`/database/query`, no transaction. drizzle-kit's SQL is idempotent as
generated (`CREATE TABLE IF NOT EXISTS`, foreign keys in `DO $$ … EXCEPTION
WHEN duplicate_object` blocks); its `--> statement-breakpoint` lines are SQL
comments and are kept so the file is upstream's byte for byte. The offline
`plan` is verified; `apply` needs a project and is not.

## SA-F — Stripe products and the pricing page (ACCEPTED)

`lib/db/seed.ts` creates the Base and Plus products and prices against the
account whose `STRIPE_SECRET_KEY` it finds (test mode, as upstream). Until
they exist the pricing page renders its hard-coded defaults with no
`priceId`; checkout then has nothing to buy. Production products are created
once by the product, as upstream's README says.

## SA-G — Local development needs a Postgres on 54322 (ACCEPTED)

`localConnectionString`, `.env.example` and upstream's Docker option in
`pnpm db:setup` all point at `postgres://postgres:postgres@localhost:54322/postgres`
— the Supabase CLI's default (`supabase start`) and upstream's
`docker-compose.yml`. Any Postgres there, or any other `POSTGRES_URL` for
the scripts, works.

## SA-H — `pnpm build` with no Stripe and no database (RESOLVED)

Nothing pre-renders against either: the root layout reads the session
cookie, so every page is dynamic at build. Since SA5 the Stripe client is
not even constructed without a key, so the build needs no placeholder.
`Checks` builds without secrets.

## SA-I — The `stripe` package's moving `LATEST` type (RESOLVED)

Upstream declares `stripe ^18.1.0` with `apiVersion: '2025-04-30.basil'`;
newer 18.x minors move the `LATEST` type and reject that literal. `stripe`
is pinned to `18.1.0`, what upstream's own lockfile resolves to.

## SA-J — A fresh product has no Stripe key and no AUTH_SECRET (RESOLVED, SA5)

A bootstrapped product is deployed by a convergence nobody attends, and
Stripe is a third party no platform brokers. Before SA5 the pricing page
answered 500 without a key and every sign-up failed without `AUTH_SECRET`.
Now the Stripe client exists only once `STRIPE_SECRET_KEY` does — pricing
renders the template's plans with checkout disabled and "Connect Stripe to
enable checkout", the checkout and portal actions and the checkout callback
send the visitor there, the webhook answers 503 — and the session key, when
`AUTH_SECRET` is unset, is 64 hex characters the environment's database
generated in migration `020_app_secrets` (`app_private.secrets`, a schema
Supabase's Data API does not expose). Anyone who can read that table can
already read every user's row; an owner who wants the key elsewhere sets
`AUTH_SECRET`, which also rotates it.

## SA-K — `wrangler.jsonc` must exist before the build (RESOLVED, SA5)

The workers-assets composition's `verify-app-structure` step runs
`test -f wrangler.jsonc` before `build-app`, in the job's fresh tree. SA1
rendered the file in the build and git-ignored it, which no lane had run yet
— every web lane would have stopped there. It is now committed as the
fixture render (tests/web holds it equal to the template), and the stage and
prod lanes re-render it from their wiring document before the build. The
SA1 build command also rendered on `dev`, which has no wiring document; dev
now verifies with the committed fixture render.

## SA-L — Supabase's Data API and the template's tables (RESOLVED, SA5)

Supabase exposes the `public` schema over PostgREST to anyone holding the
project's anon key, which is public by Supabase's design. The template's
tables (`users` with password hashes, `teams`, `invitations`, …) lived in
`public` without row-level security, because upstream assumed a private
Postgres — so every product built from this baseline would have served them.

Migration `030_row_level_security` enables RLS, with NO policy, on every
table in `public`. `anon` and `authenticated` read and write nothing through
the Data API; the app is unaffected because of the role it connects as:

- **Which role.** The cloudflare-hyperdrive root's origin is
  `database_user = "postgres"`, and the supabase root's `connection_uri` is
  `postgresql://postgres:…@db.<ref>.supabase.co:5432/postgres` — the app, and
  db-migrate's runner, are `postgres`.
- **Why it still reads its tables.** db-migrate creates them through the
  Management API's query endpoint, which is expected to run as `postgres`
  (the dashboard's SQL editor, which uses it, runs as `postgres` by
  default) — making `postgres` their owner, and a table's owner is not
  subject to RLS unless FORCE is set (it is not). That has NOT been observed
  on a live project from this repository, so the migration checks before it
  enables anything: if `postgres` neither owns every table in `public` nor
  has SUPERUSER or BYPASSRLS, it raises and enables nothing — the deploy
  stops at db-migrate, naming the tables, instead of locking the app out of
  its data. The first live bootstrap settles it.
- **The migration ledgers and the session key** live in `_migrations`,
  drizzle-kit's `drizzle` and `app_private` — schemas the Data API does not
  expose — and are left as they are.
- **Held by tests.** `apps/web/lib/db/schema.ts` declares `.enableRLS()` on
  every table, so drizzle-kit writes the statement for the next one;
  `tests/db` runs every migration in PGlite and fails if any table in
  `public` lacks RLS, if a policy or FORCE appears, or if a role with the
  Data API's grants can read or write a row — and drives the guard's refusal.
  The e2e tier does the same against a Postgres with Supabase's roles
  (`postgres` without SUPERUSER or BYPASSRLS), after a real sign-up.

## SA-M — Unmeasured wall-clock, unapplied roots (OPEN)

The card's twenty minutes is summed from the phases' estimates; no
bootstrap has been timed. Supabase project creation dominates (five to seven
minutes, Lumen's measurement), and the app's build waits on the migrations.
Neither Terraform root has been applied from this repository and no
db-migrate has run against a real project: both are validated offline, the
migrations are applied by the product's own runner to a local Postgres in
the e2e tier, and the order is proven on the product's own plan.

## SA-N — The bootstrap floor plans `modeRules` as enforced (ACCEPTED)

orun v2.58.11, the floor a bootstrap runs on, ignores per-edge `modeRules`,
so a pull-request plan it makes holds the infra edges enforced rather than
advisory. The product's own CI plans with its lane pin (v2.78.4), which
reads them; the placement tier says when it cannot check them and the e2e
tier, pinned at the lane version, does.
