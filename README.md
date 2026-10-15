# saas-starter

Vercel's [Next.js SaaS Starter](https://github.com/nextjs/saas-starter) —
Postgres through Drizzle, Stripe Checkout, Customer Portal and webhooks,
email/password auth with a JWT cookie, a session-refreshing proxy, teams with
roles, invitations and an activity log — running on **Cloudflare Workers +
Static Assets** through [`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare),
with its Postgres a **Supabase** project's database reached through
**Cloudflare Hyperdrive**, both provisioned by Terraform through
[Orun](https://github.com/sourceplane/orun) and the schema applied by Orun's
`db-migrate` — the way the [Lumen baseline](https://github.com/sourceplane/lumen)
does it — and packaged as an **Orun baseline**: one command takes a new
product from nothing to live on stage and prod, in its own repository, under
its own name, in ONE landing.

The template's code is the code. What the port changes is what the Workers
runtime and a fresh, unattended deployment force: the database client is
built per request over the Hyperdrive binding (`lib/db/drizzle.ts`), the
Stripe client exists only once a key does (so the app deploys and signs users
up with no Stripe account, and the pricing page says checkout is not
connected), and the session key defaults to one the database generates for
itself (so no secret has to be set by hand). What the baseline adds is
everything needed to make a copy of it somebody else's — built the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) builds a
product, in one landing. See [`specs/epics/saas-starter`](specs/epics/saas-starter/README.md)
for the design, the milestones and the as-built status, including every
departure.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/saas-starter
cd saas-starter
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-saas --run-hooks --resume \
  --set reponame=acme-saas --set productname="Acme Cloud" --set productdomain=acme.dev \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`saas-starter` → Build). Two phases: **`01-product`** creates the repository,
mints the five brokered credentials (Cloudflare and Supabase) and lands the
whole product as one pull request, whose convergence on `main` provisions and
deploys it per environment in a fixed order —

```
supabase ──▶ cloudflare-hyperdrive ──▶ db-migrate ──▶ web
```

— each edge `mode: enforced` on a push to main and advisory on a pull
request; then **`02-docs`** records the live deployment from probed facts.
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase.

The new repository receives the **product only** — the app, the Terraform
roots, the migrations, the tests, its CI, its tooling, a README of its own
and its operating contract — renamed throughout to the product's name,
repository, Worker, Supabase project and Hyperdrive config. None of this
repository's machinery ships. **Stripe is the owner's to connect afterwards**
(the product's README, "Connect Stripe"): no platform brokers it, so the card
asks for no Stripe key.

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, the product's README and the bootstrap's task contracts | `.baseline/` |
| The rename engine (product-name seam: `apps/web/lib/site.ts`) | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The product's context pack | `ai/context/` |
| The baseline's tests: contract, leak, offline bootstrap and plans, end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here (the product)

| Surface | Where |
|---|---|
| The product's name | `apps/web/lib/site.ts` |
| Marketing page, pricing, sign-in / sign-up, the dashboard, the Stripe routes, `/api/health` | `apps/web/app` |
| Drizzle schema, queries, the per-request client, the seed | `apps/web/lib/db` (`drizzle.ts` is `getDb()`) |
| Session (jose + bcrypt) and its key, action validation, the proxy | `apps/web/lib/auth`, `apps/web/proxy.ts` |
| Stripe client, checkout, portal, subscription sync | `apps/web/lib/payments` |
| Workers build and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` → `wrangler.jsonc` (committed), `component.yaml` |
| The schema as migrations, and Lumen's runner | `packages/db` (`@saas/db`) |
| The Supabase project, the Hyperdrive config, the migration step | `infra/terraform/supabase`, `infra/terraform/cloudflare-hyperdrive`, `infra/db-migrate` |
| Tests | `tests/web`, `tests/db` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # re-render apps/web/wrangler.jsonc from its template (committed; this changes nothing)
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

The build needs no database and no Stripe account. Running it locally — a
Postgres on `localhost:54322` (`supabase start`), `pnpm db:migrate`,
`pnpm db:seed`, `next dev` or `wrangler dev` — is in the product's README
(`.baseline/product/README.md`), which is what a product built from here
carries.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting, `middleware.ts` on the edge | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets; the middleware is `proxy.ts` (Next 16's name) and runs in the Worker |
| Postgres from the marketplace, `postgres(POSTGRES_URL)` at module scope | The Supabase project's Postgres through Hyperdrive: `getDb()` builds a `postgres` client + Drizzle per request from `env.HYPERDRIVE.connectionString`; `POSTGRES_URL` is for local scripts |
| `drizzle-kit migrate` | `infra/db-migrate` applies `packages/db/src/migrations` through Supabase's Management API per environment, after the project and the Hyperdrive config exist, before the Worker deploys |
| `AUTH_SECRET` from the setup script | Optional: unset, the session key is the one the environment's database generated (`app_private.secrets`) |
| Stripe keys in the project's env vars | Worker secrets the owner adds when ready; until then checkout says it is not connected |
| A database created by hand | `infra/terraform/supabase` (one project per environment) + `infra/terraform/cloudflare-hyperdrive` (one config per environment), ids and credentials as orun secrets |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, provisioned, deployed |

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `checks.yml` | install, wire fixture, typecheck, lint, test, build — every PR (not pushes: on main, `ci.yml` must be the only run a commit has, because the bootstrap's convergence watch takes the newest one) | yes |
| `ci.yml` | the Orun pipeline: `orun plan --changed`, then one job per lane; applies, migrates and deploys stage → prod on merge. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does | yes |
| `baseline.yml` | the baseline's own tiers: contract tests; the blueprint read by the pinned orun, the leak gate, the offline bootstrap and the product's own plans; the product built, migrated into a local Postgres, dry-deployed, served and signed up on | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |
