# saas-starter

Vercel's [Next.js SaaS Starter](https://github.com/nextjs/saas-starter) —
Postgres through Drizzle, Stripe Checkout, Customer Portal and webhooks,
email/password auth with a JWT cookie, a session-refreshing proxy, teams with
roles, invitations and an activity log — on **Cloudflare Workers + Static
Assets** through [`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare),
with its Postgres a **Supabase** project's database reached through
**Cloudflare Hyperdrive**. Terraform provisions both per environment and
Orun's `db-migrate` applies the schema, all on every merge to `main`.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace, whether Stripe is connected and the secrets the product uses into
[ai/context/deployment.md](ai/context/deployment.md); how the product deploys
and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## What is here

| Surface | Where |
|---|---|
| The product's name | `apps/web/lib/site.ts` |
| Marketing page, pricing, sign-in / sign-up, the dashboard, the Stripe routes | `apps/web/app` |
| Drizzle schema, queries, the per-request client, the seed | `apps/web/lib/db` (`drizzle.ts` is `getDb()`) |
| Session (jose + bcrypt) and its key, action validation, the proxy | `apps/web/lib/auth`, `apps/web/proxy.ts` |
| Stripe client, checkout, portal, subscription sync | `apps/web/lib/payments` |
| The database check the deploy smoke-tests | `apps/web/app/api/health/route.ts` |
| Workers build and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` → `wrangler.jsonc`, `component.yaml` |
| The schema as migrations, and their runner | `packages/db` (`@saas/db`) |
| The Supabase project, the Hyperdrive config, the migration step | `infra/terraform/supabase`, `infra/terraform/cloudflare-hyperdrive`, `infra/db-migrate` |
| Tests | `tests/web`, `tests/db` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # re-render apps/web/wrangler.jsonc from its template (it is committed)
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

The build needs no database and no Stripe account: nothing pre-renders
against either.

## Running it locally

You need a Postgres on `localhost:54322` — the Supabase CLI's default
(`supabase start`), or the Docker container `pnpm db:setup` offers — or any
Postgres whose URL you put in `POSTGRES_URL`.

1. **Environment.** Copy `apps/web/.env.example` to `apps/web/.env` and fill
   it in, or let the setup wizard do it (it can also create the Docker
   Postgres and a Stripe CLI webhook secret):

   ```bash
   pnpm --filter @app/web db:setup
   ```

   `.env` is read by `next dev`, the seed and drizzle-kit. The Worker never
   reads it: its database is the `HYPERDRIVE` binding and its secrets are
   `.dev.vars` (below).

2. **Schema.** drizzle-kit applies the migrations locally
   (`pnpm db:generate` after a schema change, `pnpm db:studio` to browse):

   ```bash
   pnpm --filter @app/web db:migrate
   ```

   The same SQL lives in `packages/db/src/migrations`, which is what CI
   applies to the real databases.

3. **Seed.** Creates the test user and team and, if `STRIPE_SECRET_KEY` is
   set, the two Stripe products (test mode):

   ```bash
   pnpm --filter @app/web db:seed      # user test@test.com / admin123
   ```

4. **Run.** Either Next's dev server, which gets the Worker's bindings
   through `getCloudflareContext()` (the `HYPERDRIVE` binding points at
   `localhost:54322` through `wrangler.jsonc`'s `localConnectionString`):

   ```bash
   pnpm --filter @app/web dev          # http://localhost:3000
   ```

   or the built Worker under `wrangler dev`, which reads
   `apps/web/.dev.vars` (copy `.dev.vars.example`; every key is optional):

   ```bash
   pnpm build
   pnpm --filter @app/web preview      # http://localhost:8787
   ```

5. **Stripe.** `stripe login`, then forward webhooks to the server you are
   running —

   ```bash
   stripe listen --forward-to localhost:3000/api/stripe/webhook
   ```

   — and test checkout with card `4242 4242 4242 4242`, any future date, any
   CVC. Without a Stripe key everything else runs, and the pricing page says
   checkout is not connected.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. Per environment the order is
enforced — **the Supabase project, then the Hyperdrive config over its
database, then the migrations, then the Worker** — because each reads what
the one before it published: the project's ref and password, the Hyperdrive
id the Worker binds, the schema the app queries. `stage` deploys first and
`prod` once stage has converged on the same commit; `dev` only verifies.
Every deploy is smoke-tested over HTTP, `/api/health` included, which
answers only when the Worker reaches a migrated database.

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare tokens and account id and the Supabase access token and org id
are brokered per run from the workspace's connections; the Supabase
project's credentials and the Hyperdrive id are published by the Terraform
applies as orun secrets. Nothing provider-shaped is stored in the repository
or in GitHub.

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after rotating a
secret, say. A component with nothing to run in that environment (a test
suite in `prod`) is left out with a notice.

## Connect Stripe

Stripe is a third party no platform brokers, so the product deploys without
it: sign-up, sign-in, teams and the dashboard work, and the pricing page says
**"Connect Stripe to enable checkout."** To turn payments on, per
environment:

1. In the Stripe dashboard (test mode first), create two products, **Base**
   and **Plus**, each with one recurring monthly price — the pricing page
   finds them by name.
2. Add a webhook endpoint at
   `https://saas-starter-web-prod.your-workers-subdomain.workers.dev/api/stripe/webhook`
   (and `-stage` for stage) for `customer.subscription.updated` and
   `customer.subscription.deleted`.
3. Set the two Worker secrets:

   ```bash
   wrangler secret put STRIPE_SECRET_KEY     --name saas-starter-web-prod
   wrangler secret put STRIPE_WEBHOOK_SECRET --name saas-starter-web-prod   # the endpoint's signing secret
   ```

Worker secrets survive every later deploy; the next request sees them.

The session cookie needs no secret from you: unless you set an
`AUTH_SECRET` Worker secret, its key is one the environment's database
generated for itself when the migrations first ran. Setting `AUTH_SECRET`
rotates it (every existing session ends).

## Custom domain

The app answers on workers.dev from its first deploy. To serve it on your
own domain, attach the domain to the Worker in Cloudflare (Workers & Pages →
`saas-starter-web-prod` → Settings → Domains & Routes), then set `BASE_URL`
in `apps/web/wrangler.template.jsonc` to it — Stripe sends the browser back
there — run `pnpm run wire:fixture`, and merge.

The repository also names the domain in one place, `BASE_DOMAIN` under each
environment's `env:` in `intent.yaml`, which the product was born with as the
reserved placeholder `saas-starter.example.com`. Nothing builds a URL from it —
Stripe's checkout and billing-portal redirects follow `BASE_URL` — so
replacing it moves nothing by itself; it records the domain. Replace it with
yours in the same pull request as `BASE_URL`.

## CI

| Workflow | What it runs |
|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes — the app built and dry-deployed for each environment, both Terraform roots checked and planned, the migrations planned and their checksums verified — with nothing applied or deployed (typecheck, lint and the tests are `pnpm` scripts you run, above); a merge applies, migrates and deploys stage → prod |
