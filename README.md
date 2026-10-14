# saas-starter

Vercel's [Next.js SaaS Starter](https://github.com/nextjs/saas-starter) —
Postgres through Drizzle, Stripe Checkout, Customer Portal and webhooks,
email/password auth with a JWT cookie, a session-refreshing proxy, teams with
roles, invitations and an activity log — running on **Cloudflare Workers +
Static Assets** through [`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare),
with its Postgres being a **Supabase** project's database reached through
**Cloudflare Hyperdrive**, both provisioned by Terraform through
[Orun](https://github.com/sourceplane/orun), and its schema applied by Orun's
`db-migrate` component — the way the
[Lumen baseline](https://github.com/sourceplane/lumen) does it.

The template's code is the code. What the port changes in it is the one thing
the Workers runtime forces — the database client is built per request over
the Hyperdrive binding (`lib/db/drizzle.ts`'s `getDb()`) instead of once at
module load — plus Next 16's `proxy.ts` name for the middleware and the
Stripe SDK's fetch transport. What it adds is the Workers build, the monorepo
wrapper, tests for the session, the proxy and the webhook, the migrations
package with Lumen's runner, three infrastructure components (the Supabase
project, the Hyperdrive config, the migration step) and the deploy contract
that threads the Hyperdrive id into the Worker per environment. See
[`specs/epics/saas-starter`](specs/epics/saas-starter/README.md) for the
design, the milestones and the as-built status, including every departure.

## What is here

| Surface | Where |
|---|---|
| Marketing page, pricing, sign-in / sign-up, the dashboard, the Stripe routes | `apps/web/app` |
| Drizzle schema, queries, the per-request client, the seed | `apps/web/lib/db` (`drizzle.ts` is `getDb()`) |
| Session (jose + bcrypt), action validation, the proxy | `apps/web/lib/auth`, `apps/web/proxy.ts` |
| Stripe client, checkout, portal, subscription sync | `apps/web/lib/payments` |
| Workers build and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc`, `component.yaml` |
| The schema as migrations + Lumen's runner | `packages/db` (`@saas/db`) |
| The migration step, the Supabase project, the Hyperdrive config | `infra/db-migrate`, `infra/terraform/supabase`, `infra/terraform/cloudflare-hyperdrive` |
| Tests | `tests/web`, `tests/db` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

The build needs no database and no Stripe account: nothing pre-renders
against either (the build script supplies a placeholder `STRIPE_SECRET_KEY`
so the module-level Stripe client can be constructed; it is never called).

## Running it locally

You need a Postgres on `localhost:54322` — the Supabase CLI's default
(`supabase start`), or the Docker container upstream's setup script offers —
or any Postgres whose URL you put in `POSTGRES_URL`.

1. **Environment.** Copy `apps/web/.env.example` to `apps/web/.env` and fill
   it in, or let upstream's wizard do it (it also creates the Docker
   Postgres and a Stripe CLI webhook secret):

   ```bash
   pnpm --filter @app/web db:setup
   ```

   `.env` is read by `next dev`, the seed and drizzle-kit. The Worker never
   reads it: its database is the `HYPERDRIVE` binding and its secrets are
   `.dev.vars` (below).

2. **Schema.** Locally, drizzle-kit applies the template's migrations as
   upstream (`pnpm db:generate` after a schema change, `pnpm db:studio` to
   browse):

   ```bash
   pnpm --filter @app/web db:migrate
   ```

   The same SQL lives in `packages/db/src/migrations` and is what CI applies
   to the real databases (below).

3. **Seed.** Creates the test user and team and the two Stripe products in
   the account `STRIPE_SECRET_KEY` names (test mode):

   ```bash
   pnpm --filter @app/web db:seed      # user test@test.com / admin123
   ```

4. **Run.** Either Next's dev server, which gets the Worker's bindings
   through `getCloudflareContext()` (the `HYPERDRIVE` binding points at
   `localhost:54322` via `wrangler.jsonc`'s `localConnectionString`, so
   `pnpm run wire:fixture` first):

   ```bash
   pnpm --filter @app/web dev          # http://localhost:3000
   ```

   or the built Worker under `wrangler dev`, which reads
   `apps/web/.dev.vars` (copy `.dev.vars.example`: `AUTH_SECRET`,
   `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `BASE_URL`):

   ```bash
   pnpm build
   pnpm --filter @app/web preview      # http://localhost:8787
   ```

5. **Stripe.** As upstream: `stripe login`, then forward webhooks to the
   server you are running —

   ```bash
   stripe listen --forward-to localhost:3000/api/stripe/webhook
   ```

   — and test checkout with card `4242 4242 4242 4242`, any future date,
   any CVC.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting, `middleware.ts` on the edge | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets; the middleware is `proxy.ts` (Next 16's name) and runs in the Worker |
| Postgres from the marketplace, `postgres(POSTGRES_URL)` at module scope | The Supabase project's Postgres through Hyperdrive: `getDb()` builds a `postgres` client + Drizzle per request from `env.HYPERDRIVE.connectionString` (the runtime refuses a socket shared across requests); `POSTGRES_URL` is for local scripts |
| `drizzle-kit migrate` | `infra/db-migrate` applies `packages/db/src/migrations` (the template's drizzle-kit SQL, verbatim) through Supabase's Management API per environment, before the Worker deploys |
| Project env vars in the dashboard | `BASE_URL`: a wrangler var per environment. `AUTH_SECRET`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`: Worker secrets (`wrangler secret put`, below) |
| The Stripe SDK over Node's `http` | `Stripe.createFetchHttpClient()`; the webhook verifies with `constructEventAsync` over SubtleCrypto |
| A database created by hand | `infra/terraform/supabase` (one project per environment) + `infra/terraform/cloudflare-hyperdrive` (one config per environment over that database), ids and credentials as orun secrets |
| Deploy on push | Orun deploys `saas-starter-web-{stage,prod}` on merge to `main`, after the Hyperdrive root and the migration step (`apps/web/component.yaml`) |

## Deploying

`.github/workflows/checks.yml` runs install, wire, typecheck, lint, test and
build on every push and pull request. `ci.yml` is the Orun pipeline: set
`execution.state.workspace` in `intent.yaml` to this product's workspace
(`orun cloud link`), connect Cloudflare **and Supabase** to that workspace,
and set the `ORUN_CI` repository variable to `true`. A merge to `main` then,
per environment: applies the Supabase root, applies the Hyperdrive root over
its database, builds `@saas/db` and applies the migrations, renders
`wrangler.jsonc` with that environment's Hyperdrive id, builds the app and
deploys the Worker to `stage`, then `prod`.

Three things are the product's to set once per environment, because no root
can mint them:

```bash
# Worker secrets (the deploy lane does not set these)
wrangler secret put AUTH_SECRET           --name saas-starter-web-stage   # openssl rand -base64 32
wrangler secret put STRIPE_SECRET_KEY     --name saas-starter-web-stage
wrangler secret put STRIPE_WEBHOOK_SECRET --name saas-starter-web-stage   # from the webhook you register below
```

- **The Worker's origin.** `BASE_URL` is where Stripe sends the browser back
  to. `apps/web/wrangler.template.jsonc`, `apps/web/component.yaml` and
  `intent.yaml` carry the same `your-workers-subdomain` placeholder: replace
  it with the account's workers.dev subdomain (or a custom domain) once.
- **The Stripe webhook.** In the Stripe dashboard, add an endpoint at
  `https://saas-starter-web-prod.<subdomain>.workers.dev/api/stripe/webhook`
  for `customer.subscription.updated` and `customer.subscription.deleted`;
  its signing secret is `STRIPE_WEBHOOK_SECRET` above.
- **The Stripe products.** Run the seed against the live account once (or
  create Base and Plus by hand); until then the pricing page shows its
  defaults with nothing to buy.
