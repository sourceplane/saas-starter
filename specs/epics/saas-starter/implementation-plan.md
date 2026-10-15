# saas-starter — implementation plan

Milestones land in order; each task is one pull request on an
`orun/SA-n-<slug>` branch with an `Orun-Task: SA-n` trailer.

## SA0 — the spec ✅

This doc set, `epic.yaml` and the task contracts, merged to `main`.

**Done when**
- the five documents and `epic.yaml` are on `main`
- `tasks/SA-1..SA-5.TaskContract.yaml` exist

## SA1 — the app on Workers ✅

`apps/web` is the upstream template with the Workers build around it:
`lib/db/drizzle.ts` exports `getDb()` (a `postgres` client + Drizzle per
call over the `HYPERDRIVE` binding, `POSTGRES_URL` when there is no
Cloudflare context) and every query and action that used the module-level
`db` says `const db = await getDb()`; `middleware.ts` is `proxy.ts`; the
Stripe client talks over fetch and the webhook verifies over SubtleCrypto.
`wrangler.template.jsonc` + `wiring.fixture.json` render the config;
`.dev.vars.example` names the Worker secrets; `tests/web` exercises the
session, the proxy and the webhook route.

**Done when**
- `pnpm install && pnpm run wire:fixture && pnpm typecheck && pnpm lint && pnpm test && pnpm build` is green locally and in `Checks`
- `wrangler dev` answers `/` with the marketing page and `/sign-in` with the form, and `/dashboard` with a 307 to `/sign-in` when signed out
- the diff against upstream is the forced set and nothing else

## SA2 — the schema through db-migrate ✅

`packages/db` (`@saas/db`) is Lumen's migration runner with the template's
drizzle-kit SQL as `010_saas_starter_schema/up.sql`, listed in
`src/manifest.ts` with its checksum; `infra/db-migrate` applies it per
environment after the `supabase` root; `tests/db` checks the manifest and
the offline plan.

**Done when**
- `pnpm --filter @saas/db run manifest:check` passes
- `node packages/db/dist/runner/cli.js plan --env stage` lists both migrations as pending (offline)
- `tests/db` is green; the component's `path` and `dependsOn` are Lumen's

## SA3 — Supabase and Hyperdrive from Terraform ✅

`infra/terraform/supabase` provisions a project per environment and
publishes its credentials; `infra/terraform/cloudflare-hyperdrive` creates
the Hyperdrive config over that database and publishes
`WIRING_CLOUDFLARE_HYPERDRIVE`; `apps/web/component.yaml` depends on both
(the second directly, the first through `db-migrate`) and declares the
`secretEnv` the deploy renders from.

**Done when**
- `terraform init -backend=false && terraform validate` passes on both roots
- the component's `secretEnv` keys match the roots' `secretOutputs`
- the fixture's wiring keys match the template's tokens (`wire:fixture` renders)

## SA4 — ready to instantiate ✅

README (local development with the Supabase CLI or any Postgres, the seed,
Stripe, the Worker secrets; test, preview, deploy), `IMPLEMENTATION-STATUS.md`
with PRs and departures, epic `completed`.

**Done when**
- the README quick start works from a fresh clone
- the status file lists every PR and departure

## Sequencing note

SA1's component already names `cloudflare-hyperdrive` and `db-migrate` and
the Hyperdrive wiring secret; SA2 and SA3 are the halves that make those
names true. Applying them needs a workspace with Supabase and Cloudflare
connections; until then the Orun lane is gated and `Checks` is the merge
gate. SA4 is documentation over all three.
