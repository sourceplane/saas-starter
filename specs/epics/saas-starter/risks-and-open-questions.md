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
cookie, so every page is dynamic at build, and the Stripe client is only
constructed, never called. `Checks` builds without secrets.

## SA-I — The `stripe` package's moving `LATEST` type (RESOLVED)

Upstream declares `stripe ^18.1.0` with `apiVersion: '2025-04-30.basil'`;
newer 18.x minors move the `LATEST` type and reject that literal. `stripe`
is pinned to `18.1.0`, what upstream's own lockfile resolves to.
