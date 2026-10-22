# saas-starter — operating contract (for humans and agents)

This is the standing guide to how this product is deployed and operated.
Instance facts (live URLs, workspace, whether Stripe is connected, the
secrets inventory) live in [deployment.md](deployment.md), rendered from
probed reality by the bootstrap's `02-docs` phase; this file is the contract
that stays true between deployments. It is written to give an agent with
repository read access enough context to reason about and operate the product
without any other source.

## What this system is

Vercel's Next.js SaaS Starter — email/password auth with a JWT cookie, teams
with roles and invitations, an activity log, Stripe subscriptions — on
Cloudflare Workers, with its Postgres a Supabase project reached through
Cloudflare Hyperdrive, expressed as an Orun component-native desired-state
repo. Seven components:

- **`infra/terraform/supabase`** (`supabase`) — one Supabase project per
  environment. Its apply publishes `SUPABASE_PROJECT_REF`,
  `SUPABASE_DB_PASSWORD` and `SUPABASE_DB_URL` onto the environment's secret
  rung.
- **`infra/terraform/cloudflare-hyperdrive`** (`cloudflare-hyperdrive`) — one
  Hyperdrive config per environment over that database. Its apply publishes
  `WIRING_CLOUDFLARE_HYPERDRIVE` (the config's id and name).
- **`infra/db-migrate`** (`db-migrate`) — applies `packages/db`'s migrations
  to the environment's database through Supabase's Management API. Each
  migration is recorded with its checksum in `_migrations.applied`; only the
  missing ones apply.
- **`packages/db`** (`db`) — the migrations and their runner.
- **`apps/web`** (`web`) — the app: Next.js built by `@opennextjs/cloudflare`
  into one Worker plus Static Assets. It reaches Postgres through its
  `HYPERDRIVE` binding, one client per request (`lib/db/drizzle.ts`).
- **`tests/web`**, **`tests/db`** — vitest suites, verified on the `dev` rung.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and test, nothing deploys.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. Per environment, in this order — each edge `mode: enforced` on a push to
   main, advisory on a pull request (which deploys nothing):
   **`supabase` → `cloudflare-hyperdrive` → `db-migrate` → `web`.** A job
   resolves its secrets when it starts, so each one reads what the apply
   before it published. The app's deploy re-renders `apps/web/wrangler.jsonc`
   from `WIRING_CLOUDFLARE_HYPERDRIVE` before it builds, deploys
   `saas-starter-web-<env>`, and smoke-tests it: the home page, and
   `/api/health`, which answers 200 only when the database is reachable
   through Hyperdrive and migrated.
4. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
5. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "product
  converged"; probe the URLs instead.
- `apps/web/wrangler.jsonc` is committed as the render of
  `wrangler.template.jsonc` from `wiring.fixture.json` (a placeholder
  Hyperdrive id): edit the template and run `pnpm run wire:fixture`. The
  deploy lanes render the real one in their own job tree; never commit a
  real id.
- Every table in `public` has row-level security and no policy. Supabase's
  Data API serves `public` to the anon key, so this is what keeps the users
  table (password hashes included) out of it; the app is unaffected because
  it connects as `postgres`, the tables' owner. Give a new table
  `.enableRLS()`; never `FORCE` it, and never add a policy for `anon` without
  meaning to publish that table.
- A migration is immutable once applied: its checksum is in
  `packages/db/src/manifest.ts` and in the database's ledger. Change the
  schema with a NEW migration (in `packages/db/src/migrations`, and its
  drizzle-kit twin in `apps/web/lib/db/migrations` for local databases).

## Secrets model

- **Brokered provider secrets**, minted per run from the workspace's
  connections — no long-lived values at rest, nothing to rotate by hand:
  `CLOUDFLARE_API_TOKEN` (Workers deploy), `CLOUDFLARE_HYPERDRIVE_TOKEN`
  (Hyperdrive — the deploy token deliberately cannot touch it),
  `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_ACCESS_TOKEN` (project create and
  migrations) and `SUPABASE_ORG_ID`.
- **Published by the applies** onto the stage and prod rungs:
  `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`,
  `WIRING_CLOUDFLARE_HYPERDRIVE`.
- **Worker secrets the owner adds**, because no platform brokers Stripe:
  `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` (below). Until they exist
  the pricing page says checkout is not connected, the checkout and portal
  actions send visitors there, and the webhook answers 503.
- **The session key.** `AUTH_SECRET`, when set as a Worker secret, signs the
  session cookie. Unset, the key is the one the environment's database
  generated for itself (`app_private.secrets`, migration `020_app_secrets`) —
  so a fresh deployment signs users up without any secret set by hand.
  Setting `AUTH_SECRET` rotates it: every existing session ends.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Connect Stripe

Per environment (`stage`, `prod`), in the Stripe account you want to charge
from (test mode first):

1. Create two products, **Base** and **Plus**, each with one recurring
   monthly price — the pricing page finds them by those names. (Or run
   `pnpm --filter @app/web db:seed` with `STRIPE_SECRET_KEY` and a local
   `POSTGRES_URL`: it creates both, and a local test user.)
2. Add a webhook endpoint at
   `https://saas-starter-web-<env>.your-workers-subdomain.workers.dev/api/stripe/webhook`
   for `customer.subscription.updated` and `customer.subscription.deleted`.
3. Set both Worker secrets:

   ```bash
   wrangler secret put STRIPE_SECRET_KEY     --name saas-starter-web-<env>
   wrangler secret put STRIPE_WEBHOOK_SECRET --name saas-starter-web-<env>   # the endpoint's signing secret
   ```

Worker secrets survive every later deploy; nothing in CI touches them. The
pricing page shows the live plans from the next request on. Re-running the
bootstrap's `02-docs` phase records the change in
[deployment.md](deployment.md).

## Verifying the system

```bash
# the app and its database path on each environment (also recorded, probed, in deployment.md)
curl -s -o /dev/null -w '%{http_code}\n' https://saas-starter-web-stage.your-workers-subdomain.workers.dev/
curl -s https://saas-starter-web-prod.your-workers-subdomain.workers.dev/api/health

# workspace readiness (integrations + repository link)
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| change the schema | add the table to `apps/web/lib/db/schema.ts` with `.enableRLS()`, `pnpm --filter @app/web db:generate`, copy the SQL into a new `packages/db/src/migrations/<nnn>_<name>/up.sql` and the manifest (`pnpm --filter @saas/db run manifest:fix` for its checksum), merge — db-migrate applies it before the app deploys. `pnpm test` fails on a table in `public` without row-level security |
| redeploy without a change | edit the last line of the component's `component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| connect Stripe | above |
| rotate the session key | `wrangler secret put AUTH_SECRET --name saas-starter-web-<env>` (32+ random bytes); every session ends |
| serve a custom domain | attach it to the Worker in Cloudflare (README, "Custom domain"), change `BASE_URL` in `apps/web/wrangler.template.jsonc` (Stripe redirects back to it), and replace the placeholder `saas-starter.example.com` in `intent.yaml`'s `BASE_DOMAIN` with it (a record; nothing builds a URL from it) |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

Structural changes (a second Worker, a queue, another data store) follow the
same contract that deployed the product: add a component under `apps/`,
`infra/` or `packages/` with a `component.yaml` — declaring `dependsOn` on
any infrastructure whose published secrets it reads, enforced on main — land
it as a pull request, and the convergence run applies it.
