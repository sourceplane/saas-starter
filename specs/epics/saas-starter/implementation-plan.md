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

## SA5 — a baseline (SA-6) ✅

The repository becomes an Orun baseline on the Lumen conventions, built the
way cirrus-baseline v22 builds a product — in ONE landing:

- `blueprint.yaml` (the card: `requires [github, cloudflare, supabase]`, the
  five brokered secrets as a preview, the programme `01-product`, `02-docs`)
  and `repo-blueprint.yaml` (every module placed by `01-product` and landed as
  one pull request; `02-docs` hook-only);
- the components' edges `mode: enforced` on a push to main, advisory on a
  pull request, so one convergence runs supabase → cloudflare-hyperdrive →
  db-migrate → web per environment;
- the app deployable with no Stripe key and no hand-set secret: the Stripe
  client is lazy and checkout says it is not connected; the session key
  defaults to one the database generates (migration `020_app_secrets`);
- `wrangler.jsonc` committed as the fixture render, so the composition's
  pre-build structure check passes in a fresh checkout;
- `.baseline/`, the rename engine, the bootstrap helpers, the deployment
  record, `ai/context/`, `testing/` and the `baseline.yml` / `tag.yml` lanes.

**Done when**
- orun reads the build document at the bootstrap floor (v2.58.11), the lane
  pin (v2.78.4) and 2.79.0, and the card agrees with it
- the product's own `orun plan --trigger github-push-main` shows the order,
  enforced; a pull request's plan holds the same edges advisory
- the e2e tier migrates a local Postgres with the product's own runner, builds
  in the job tree orun stages, and signs a user up with no Stripe key

## SA6 — the cirrus standard (SA-7) ✅

Bring the baseline to cirrus-baseline's standard, with nothing about the app
itself changing.

- **No kiox.** `kiox.yaml`/`kiox.lock` pinned an orun (v2.15.0) that nothing
  ran: every workflow installs orun itself through `orun-action` with its own
  `version:`. The files, their two modules and the rebrand's skip entry go.
- **Component docs.** `tooling/catalog/gen-component-docs.py` writes each of
  the seven components' `docs/overview.md`, `docs/architecture.md` and
  `docs/runbook.md` from what the component declares, as cirrus-baseline's
  do; the pages ship with the component. Baseline CI runs it with `--check`.
- **The context pack.** `ai/context/current.md`, `decisions.md` and
  `open-risks.md` beside the two pages a product ships with — this
  repository's own, so no module places them.
- **Status that agrees with the tags.** SA5 is shipped and tagged.
- **The subdomain from the Cloudflare connection (SA-8).** The card declares
  `subdomain` as `from: connection.cloudflare.workersSubdomain`, as
  cirrus-baseline does since baseline-v23, so the console asks for nothing the
  connection already knows; `testing/manifest.test.sh` requires the source's
  provider in `spec.requires.integrations`.

**Done when**
- nothing outside this milestone's own record names kiox (`git grep -i
  kiox`), and the leak gate and the offline bootstrap pass without the two
  modules
- the docs check is green in Baseline CI
- the card renders no subdomain field, and the manifest gate fails a
  `connection.` source whose provider the card does not require
- this file, the status file and `epic.yaml` agree

## Sequencing note

SA1's component already names `cloudflare-hyperdrive` and `db-migrate` and
the Hyperdrive wiring secret; SA2 and SA3 are the halves that make those
names true. Applying them needs a workspace with Supabase and Cloudflare
connections; until then the Orun lane is gated and `Checks` is the merge
gate. SA4 is documentation over all three.
