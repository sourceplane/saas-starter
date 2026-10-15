# Epic: saas-starter (SA)

**Vercel's Next.js SaaS Starter is the template whose shape is a product: a database with users, teams and subscriptions, Stripe for the money, a JWT cookie for the session, server actions for every mutation. None of that cares whether the server is a Vercel function or a Cloudflare Worker — except the database socket. The port keeps the code and moves three things: where the app runs (an OpenNext Worker + Static Assets), where the Postgres comes from (a Supabase project fronted by Cloudflare Hyperdrive, both from Terraform through Orun), and who applies the schema (Orun's db-migrate, from the drizzle-kit SQL the template already ships). The one line of code the Workers runtime forces to change is the database client: a module-level `postgres(POSTGRES_URL)` becomes a per-request `getDb()` over the Hyperdrive binding.**

The upstream code stays the code: the Drizzle schema and queries, the server actions and their zod validation, the jose session and bcrypt passwords, the middleware (under Next 16's name, `proxy.ts`), the Stripe checkout, portal and webhook handling, the dashboard, the pricing page and the marketing page. The port adds the Workers build, the monorepo wrapper, a test package over the session, the proxy and the webhook, the migrations package and its runner, and three infrastructure components — the Supabase project, the Hyperdrive config fronting it, and the migration step — plus the deploy contract that threads the Hyperdrive id into the Worker per environment.

## Status

| Field | Value |
|-------|-------|
| Status | ✅ SA0–SA4 shipped (#1–#5) · 🔄 SA5 — a baseline (SA-6) in review. The Supabase and Hyperdrive applies, a live db-migrate apply and a live deploy are gated on a linked workspace |
| Cluster | **SA** (SA0–SA5) |
| Owner(s) | `apps/web` (the app) · `packages/db` (the migrations and their runner) · `tests/web`, `tests/db` · `infra/terraform/supabase`, `infra/terraform/cloudflare-hyperdrive`, `infra/db-migrate` |
| Builds on | `lumen` conventions — the `supabase` and `cloudflare-hyperdrive` Terraform roots, `@saas/db` + `db-migrate`, the per-request `postgres` client; `cirrus-baseline` conventions for the repository shape |
| Upstream | [nextjs/saas-starter](https://github.com/nextjs/saas-starter) (`6e33e58`, Next 15.6 canary) |
| Changes | Adds the Workers build, the monorepo wrapper, tests, the migrations package, the three infra components and the deploy contract; in the template's code: `lib/db/drizzle.ts` (per-request client), `middleware.ts` → `proxy.ts`, the Stripe client's fetch transport and the webhook's async signature check |
| Decisions locked | (1) OpenNext on Workers + Static Assets. (2) Drizzle over a Postgres socket through Hyperdrive, not PostgREST and not D1. (3) A `postgres` client per request — never a module-level pool. (4) `wrangler.jsonc` rendered from the template: committed as the fixture render (the composition checks it exists before the build), re-rendered per environment from the Hyperdrive wiring document by the deploy lanes (SA5; it was never committed before). (5) drizzle-kit stays for local development; the runner applies in CI. (6) `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` are Worker secrets the owner adds when ready — the app deploys and serves without them (SA5); `AUTH_SECRET` is optional, the database generating the session key otherwise (SA5); `BASE_URL` is a wrangler var. (7) Infra before app on main: supabase → cloudflare-hyperdrive → db-migrate → web, enforced; advisory on pull requests (SA5). |
| Gate | SA1 is the first user-visible rung. SA2 and SA3 need a workspace with Supabase and Cloudflare connections to apply; they are verified by `plan` and `terraform validate`. |
| Shipped as | `main` after [#5](https://github.com/sourceplane/saas-starter/pull/5); verified locally under `wrangler dev` with the fixture config and a throwaway `.dev.vars` |

## Read order

1. `design.md` — what maps to what, the request → Hyperdrive → Postgres flow, the env/secret flow, the alternatives rejected
2. `implementation-plan.md` — the milestones and what "done" means for each
3. `risks-and-open-questions.md` — what could go wrong and what was decided
4. `IMPLEMENTATION-STATUS.md` — what actually shipped (kept distinct from intent)

## Milestones at a glance

| Milestone | What it lands | Done when |
|---|---|---|
| SA0 — the spec | this doc set and the task contracts | merged on `main` |
| SA1 — the app on Workers | `apps/web` built by OpenNext with `getDb()` over Hyperdrive, rendered wrangler config, `tests/web` | `wrangler dev` serves `/` and `/sign-in` and redirects `/dashboard`; Checks green |
| SA2 — the schema through db-migrate | `packages/db`, `tests/db`, `infra/db-migrate` | the manifest checks, the runner plans offline, the component depends on the root |
| SA3 — Supabase and Hyperdrive from Terraform | `infra/terraform/supabase`, `infra/terraform/cloudflare-hyperdrive` | both roots validate; the wiring keys match the template's tokens |
| SA4 — ready to instantiate | README, as-built status | a reader can run, seed, test, preview and deploy it |
| SA5 — a baseline | card, build document, rename, bootstrap tooling, the product's README and context pack, tests | a new product goes from nothing to live on stage and prod in one landing, with no Stripe key; Baseline CI green |
