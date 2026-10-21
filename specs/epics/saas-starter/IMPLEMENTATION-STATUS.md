# saas-starter (SA) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream template.

| Milestone | State | PR |
|---|---|---|
| SA0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/saas-starter/pull/1) |
| SA1 — the app on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/saas-starter/pull/2) |
| SA2 — the schema through db-migrate | ✅ Shipped (planned offline; apply gated on a linked workspace) | [#3](https://github.com/sourceplane/saas-starter/pull/3) |
| SA3 — Supabase and Hyperdrive from Terraform | ✅ Shipped (validated; apply gated on a linked workspace) | [#4](https://github.com/sourceplane/saas-starter/pull/4) |
| SA4 — ready to instantiate | ✅ Shipped | [#5](https://github.com/sourceplane/saas-starter/pull/5) |
| SA5 — a baseline | ✅ Shipped | [#6](https://github.com/sourceplane/saas-starter/pull/6) (SA-6), tagged `baseline-v1` |
| SA6 — the cirrus standard | ✅ Shipped | [#7](https://github.com/sourceplane/saas-starter/pull/7) (SA-7, SA-8), tagged `baseline-v2` |

## Departures from the upstream template

Upstream is [nextjs/saas-starter](https://github.com/nextjs/saas-starter)
at `6e33e58` (Next 15.6.0-canary.59). `apps/web` is that tree; the diff
against it is the list below and nothing else.

### The database client is built per request (`lib/db/drizzle.ts`) — THE departure

Upstream creates `postgres(process.env.POSTGRES_URL)` and `drizzle(client)`
once at module load and every query and action imports that `db`. On
Cloudflare Workers the connection string is the Hyperdrive binding's
(`getCloudflareContext().env.HYPERDRIVE.connectionString`), and the runtime
refuses to reuse a socket opened by another request ("Cannot perform I/O on
behalf of a different request" — the incident Lumen's
`packages/db/src/hyperdrive/executor.ts` records). `drizzle.ts` therefore
exports an async `getDb()` that builds `postgres(connectionString, { max: 5,
fetch_types: false, prepare: false })` and `drizzle(client, { schema })` per
call, falling back to `POSTGRES_URL` when there is no Cloudflare context
(`next dev` before the bindings are up, the seed and setup scripts,
drizzle-kit, tests). The 17 places that used the module-level `db`
(`lib/db/queries.ts`, `app/(login)/actions.ts`, `app/api/stripe/checkout/route.ts`,
`lib/db/seed.ts`) open with `const db = await getDb();`. The schema, the
query bodies and the actions are as written.

### `middleware.ts` → `proxy.ts`

Next 16's name for the same file; the exported function is `proxy`. The
logic (session cookie check, jose re-sign on GET, redirect to `/sign-in`) is
unchanged. The `runtime: 'nodejs'` segment config is dropped: Next 16
rejects route segment config in the proxy file ("Proxy always runs on
Node.js runtime"). OpenNext bundles it as Node.js middleware (its
"experimental" warning; works).

### Stripe over fetch, webhook signature over SubtleCrypto

`lib/payments/stripe.ts` constructs the client with `httpClient:
Stripe.createFetchHttpClient()` (no Node `http` agent on Workers);
`app/api/stripe/webhook/route.ts` verifies with `await
stripe.webhooks.constructEventAsync(payload, signature, secret, undefined,
Stripe.createSubtleCryptoProvider())` instead of the synchronous
`constructEvent`. Same inputs, same 400 on a bad signature (tested).

### `next.config.ts`: no `experimental.ppr`, no `clientSegmentCache`

Next 16.3.8 hard-errors on `experimental.ppr` ("merged into
`cacheComponents`") and no longer knows `experimental.clientSegmentCache`.
Turning on `cacheComponents` would make the pricing page's `revalidate` an
error and demand a Suspense boundary above the root layout's cookie read —
template rewrites — so both keys are dropped. Every route renders per
request either way (the root layout reads the session cookie), which is
what the build reports: all `ƒ`. Added: `output: "standalone"`,
`outputFileTracingRoot` (OpenNext), `initOpenNextCloudflareForDev()`.

### The pricing page renders per request

`app/(dashboard)/pricing/page.tsx` had `export const revalidate = 3600`:
pre-rendered at build with the account's Stripe key, refreshed hourly. On
Workers the build has no Stripe key (and `stripe` 18 throws at module load
without one, so the build script supplies a placeholder it never calls),
and the static-assets incremental cache is read-only, so an ISR page would
freeze at build with whatever the build saw. It is `export const dynamic =
'force-dynamic'` now: prices and products are read from Stripe when the
page is requested. The R2 incremental cache is the path back to an hourly
cache.

### `tsconfig.json`: `jsx` is `react-jsx`

Next 16's own mandatory rewrite on first build ("next.js uses the React
automatic runtime"); `.next/dev/types/**/*.ts` added to `include` for the
dev type output.

### eslint-config-next 16 flat config, rules relaxed for the template's code

Upstream has no eslint config. `eslint.config.mjs` is what `create-next-app`
writes for Next 16, with `react/no-unescaped-entities` and `prefer-const`
off, `@typescript-eslint/no-explicit-any` off (`ActionState`'s index
signature) and `@typescript-eslint/no-unused-vars` a warning that ignores
catch parameters (two unused imports, the setup script's catch blocks) — the
template is kept as written rather than edited to satisfy the linter.

### Versions

| Package | Version | Why |
|---|---|---|
| next | 16.3.8 | newest inside `@opennextjs/cloudflare` 1.20.11's range (16.4.x fails at boot — playbook) |
| react, react-dom | ^19.2.1 (19.3.1 installed) | Next 16 needs React 19.2+; upstream pinned 19.1.0 |
| stripe | 18.1.0 (exact) | newer 18.x minors move the `LATEST` apiVersion type and reject the template's `'2025-04-30.basil'`; this is what upstream's lockfile resolves |
| @opennextjs/cloudflare | ^1.20.11 | static-assets incremental cache + `populateCache local`; Next 16 `proxy.ts` as Node.js middleware |
| postgres, drizzle-orm, drizzle-kit, jose, bcryptjs, zod, swr, radix-ui, tailwindcss 4.1.7 | as upstream | — |
| wrangler | ^4.151.0 | the `hyperdrive[].localConnectionString` config |

## Verified

- Local (Node 25, pnpm 10.12.1): `pnpm run wire:fixture`, `pnpm typecheck`,
  `pnpm lint` (0 errors, 4 warnings in upstream code), `pnpm test` (11 tests
  in `tests/web`, 3 in `tests/db`), `pnpm build` green — all routes `ƒ`,
  proxy bundled as middleware, `.open-next/worker.js` + assets produced.
- `pnpm --filter @saas/db run manifest:check` green; `node
  packages/db/dist/runner/cli.js plan --env stage` (offline) lists
  `000_control_baseline` and `010_saas_starter_schema`; `apply` refuses
  without `SUPABASE_ACCESS_TOKEN`, as designed.
- `terraform init -backend=false && terraform validate` green on
  `infra/terraform/supabase` (supabase/supabase 1.5.1) and
  `infra/terraform/cloudflare-hyperdrive` (cloudflare/cloudflare 4.52.9).
- `wrangler dev` over the built Worker with the fixture config and a
  throwaway `.dev.vars` (no Postgres running): `/` 200 with the marketing
  page and the signed-out header; `/sign-in`, `/sign-up` 200; `/dashboard`
  and `/dashboard/activity` signed out 307 → `/sign-in`; `/api/user` and
  `/api/team` signed out 200 `null` (no database touched); `POST
  /api/stripe/webhook` without and with a bad `stripe-signature` 400
  ("Webhook signature verification failed", through SubtleCrypto); `/nope`
  404 with the template's page; `/pricing` 500 — Stripe answers 401 to the
  placeholder key, which is the expected unconfigured state; with a
  jose-signed `session` cookie `/dashboard` 200 with the dashboard shell and
  a re-signed `Set-Cookie` (HttpOnly, Secure, SameSite=lax, +1 day), while
  `getUser()` logs `connection attempt failed` and `/api/user` answers 500:
  the query went through `env.HYPERDRIVE` to `localhost:54322`, where
  nothing was listening — the binding path, exercised.
- CI: `Checks` green on #2, #3 and #4 (#5 is documentation).
- Not verified: an apply of either Terraform root, a `db-migrate` apply, a
  live deploy and a checkout against a real Stripe account — all need the
  product linked to an Orun workspace with Supabase and Cloudflare
  connections (`ORUN_CI` variable) and the Worker secrets set (README →
  Deploying).

## SA5 — a baseline (SA-6)

The repository is an Orun baseline on the Lumen conventions, built the way
cirrus-baseline v22 builds a product: ONE landing. `blueprint.yaml` is the
card (`requires: [github, cloudflare, supabase]`; the five brokered keys —
`CLOUDFLARE_API_TOKEN` workers-deploy, `CLOUDFLARE_HYPERDRIVE_TOKEN`
hyperdrive-edit, `CLOUDFLARE_ACCOUNT_ID` account-id, `SUPABASE_ACCESS_TOKEN`
management-access, `SUPABASE_ORG_ID` org-id — as a preview; programme
`01-product`, `02-docs`); `repo-blueprint.yaml` places every module in
`01-product`, brands it, links the repository, reconciles the five keys and
lands it as one pull request, then awaits the convergence, the four published
secrets on stage and prod and `/` + `/api/health`; `02-docs` restores the
promotion gate and dev's lanes and renders the record. The machinery is
portfolio-starter-kit's (`baseline-v2`) — `.baseline/`, the rename engine,
the bootstrap helpers, the deployment-record hook, `ai/context/`, `testing/`,
`baseline.yml`, `tag.yml`, `ci.yml`'s `linked` gate — adapted to two phases.

### Departures, in the product

- **Stripe is optional** (`lib/payments/stripe.ts`). Upstream built the client
  at module load from `STRIPE_SECRET_KEY!`. `getStripe()` builds it only once
  the key exists; `stripeConfigured()` gates the pricing page (the template's
  plans, checkout disabled, "Connect Stripe to enable checkout"), the checkout
  and portal actions and the checkout callback (→ `/pricing`), and the webhook
  (503 "Stripe is not connected." until both keys are set). The build no
  longer supplies a placeholder key. The seed calls `getStripe()`.
- **The session key defaults to the database's** (`lib/auth/secret.ts`,
  migration `020_app_secrets` and its drizzle-kit twin `0001_app_secrets`).
  `AUTH_SECRET` wins when set; otherwise the key is 64 hex characters the
  database generated into `app_private.secrets`, read once per isolate.
  `session.ts` resolves the key per use instead of encoding `AUTH_SECRET` at
  module load.
- **Row-level security on every table in `public`** (migration
  `030_row_level_security`, drizzle-kit twin `0002`, `.enableRLS()` in
  `schema.ts`), with no policy: Supabase's Data API serves `public` to the
  anon key, and the template's tables — password hashes included — had none
  (SA-L). The app connects as `postgres`, the tables' owner; the migration
  refuses to run if that role would be locked out. `tests/db` (PGlite) and
  the e2e hold it.
- **`/api/health`** (new): 200 only when the database behind the HYPERDRIVE
  binding answers and both `public.users` and `app_private.secrets` exist.
  The deploy's smoke and both phases' probes read it.
- **The product's name is one seam** (`lib/site.ts`, `SITE_NAME`): the header
  beside the logo (upstream's literal "ACME") and the `<title>` (upstream:
  "Next.js SaaS Starter"). The marketing page's links to the upstream
  template stay upstream's; the rename engine protects them.
- **`apps/web/wrangler.jsonc` is committed** — the fixture render of the
  template — because the composition checks for it before the build. The
  stage and prod lanes re-render it from their wiring document; dev verifies
  with the fixture (SA-K). `tests/web` holds the two equal.
- **The deploy order is enforced on main** (component `dependsOn` with
  `mode: enforced` and an advisory `modeRules` entry for pull requests):
  `cloudflare-hyperdrive` → `supabase`; `db-migrate` → `supabase`,
  `cloudflare-hyperdrive` (new: the migrations run last before the app);
  `web` → `cloudflare-hyperdrive`, `db-migrate`.
- **The supabase root publishes Lumen's three outputs**
  (`SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`) and no
  longer reads the project's API keys, which nothing here uses (the
  `supabase_apikeys` block and `SUPABASE_URL`/`_ANON_KEY`/`_SERVICE_ROLE_KEY`/
  `WIRING_SUPABASE` are gone). Both roots carry Lumen's
  `.terraform.lock.hcl`.
- **stack-tectonic 0.19.0** (was 0.18.2; not 0.20.0, whose lane-scoped install
  Turbopack refuses), **`checks.yml` on pull requests only**, `ci.yml`'s
  `linked` gate in place of the `ORUN_CI` variable and its lanes on v2.78.4.
- `packages/db`'s runner reads `SUPABASE_API_URL` (default
  `https://api.supabase.com`) so the e2e can point it at a stand-in.
- `apps/web/README.md` describes the app as it runs here (upstream's text is
  upstream's repository); `intent.yaml`'s docs pages are the product's
  `ai/context/` pages.

### Verified (SA5)

See the pull request for the run log. In short: the repository's checks
(`pnpm install --frozen-lockfile`, `wire:fixture`, typecheck, lint, test —
37 tests: 27 in `tests/web`, 10 in `tests/db` — build); every
`testing/*.test.sh`; `orun new --status` at v2.58.11, v2.78.4 and 2.79.0;
`orun validate`; `orun work check`; `terraform fmt`, `init -backend=false`
and `validate` on both roots. Not verified: a Terraform apply, a db-migrate
apply against a real Supabase project, a live deploy, a live bootstrap, and
checkout against a real Stripe account (SA-M).

## The cirrus standard (SA6)

Nothing about the app changed. What changed is the baseline around it:

| What | Before | After | Why |
|---|---|---|---|
| orun pin | `kiox.yaml` (v2.15.0) + `kiox.lock`, shipped to every product | gone; orun is pinned where it runs, the `orun-action` `version:` in each workflow | nothing ran the kiox pin, and it disagreed with the lanes (v2.78.4) |
| `root-kiox`, `root-kiox-lock` modules | in `01-product` | removed (`testing/phases.test.sh` and the rebrand's skip list follow) | a product is placed with 159 files: 140 − 2 kiox + 21 docs pages |
| component docs | none | `docs/overview.md`, `architecture.md`, `runbook.md` beside each of the seven `component.yaml` | cirrus-baseline documents every component; the workspace Docs library renders `docs/` beside each manifest |
| how the docs stay true | — | `tooling/catalog/gen-component-docs.py` derives them from the manifest, the Worker config, Terraform, migrations and package scripts; Baseline CI runs it with `--check` | a hand-written copy of a manifest drifts silently |
| context pack | `operations.md`, `deployment.md` | plus `current.md`, `decisions.md`, `open-risks.md` | cirrus-baseline's shape; the three new pages are this repository's own and no module places them (the leak gate still allows exactly two) |
| status | SA5 "in review", on a branch | SA5 shipped and tagged `baseline-v1`; `design.md` §3/§5 list the four migrations and the supabase root as SA5 left them | the tag existed; the documents had not caught up |

### The subdomain from the Cloudflare connection (SA-8)

`subdomain` was the one input an operator typed that the platform could
answer itself: it belongs to the Cloudflare account the same way its id does,
and it has exactly one right answer. A typed one could only be wrong, and
wrong showed up after deploy — in the `BASE_URL` Stripe returns to, the
deploy's smoke, the phase probes and the console's verify URLs.
`blueprint.yaml` now declares `from: connection.cloudflare.workersSubdomain`,
as cirrus-baseline does since baseline-v23: the Cloudflare integration reads
the subdomain at connect and on its hourly health check, and the bootstrap
door fills the input from the connection the build is bound to — the same one
`CLOUDFLARE_ACCOUNT_ID` and the deploy tokens mint from. The console renders
no field for it, and an account with no workers.dev subdomain is refused at
the door with the fix named.

- `testing/manifest.test.sh` takes cirrus-baseline's rule verbatim (the file
  is now byte-identical to cirrus-baseline's): the source is accepted, and
  only when `spec.requires.integrations` lists its provider.
- `repo-blueprint.yaml` keeps the input and its default; it, `BOOTSTRAP.md`
  and `docs/phases/README.md` say only a hand-run build passes
  `--set subdomain`.
- Nothing a product carries changes: the rename, `BASE_URL`, the smoke and
  the probes read the value exactly as before.

Verified:

- `testing/{manifest,phases,coverage,rebrand,retouch,bootstrap-defer}.test.sh`
  green; `gen-component-docs.py --check` green (7 components).
- Mutation: with `cloudflare` dropped from `spec.requires.integrations`,
  `manifest.test.sh` fails with exactly one finding, naming
  `inputs[subdomain]`; restored, it passes.
- At v2.58.11 (the blueprint job's pin): `orun new --status` reads the
  document (`01-product` pending, 159 files); `testing/leak.test.sh` 159
  files derived, 157 text files read; `testing/placement.test.sh` 159 files
  placed, both landings, the product's own plan orders supabase →
  cloudflare-hyperdrive → db-migrate → web on stage and prod, enforced.
- `orun task check SA-8` complete.

## Verified (SA6)

- `testing/{manifest,phases,coverage,rebrand,retouch,bootstrap-defer}.test.sh`
  green; `gen-component-docs.py --check` green (7 components, 21 pages).
- `orun new --status` at v2.58.11: `01-product` 159 files (140 on
  `baseline-v1`), `02-docs` hook-only.
- `testing/leak.test.sh` at v2.58.11: 159 files derived, 157 text files
  read; ai/context still exactly the two declared pages; the generated pages
  name no factory path.
- `testing/placement.test.sh` at v2.58.11: 159 files placed, both landings,
  branded, re-tenanted, record rendered; the product's own plan orders
  supabase → cloudflare-hyperdrive → db-migrate → web on stage and prod,
  enforced; `--resume` changes nothing.
- `pnpm install --frozen-lockfile`, `wire:fixture` (the tree unchanged),
  `typecheck`, `lint` (0 errors, upstream's 4 warnings), `test` (37 tests:
  27 in `tests/web`, 10 in `tests/db`), `build` green.
- `testing/e2e.test.sh` at v2.78.4 green: the finished product passes the
  Checks sequence; the stage db-migrate lane applies all four migrations to
  a local Postgres with Supabase's roles and a second apply applies nothing;
  the stage web lane's install, `verify-app-structure`, `build-app`,
  `verify-build-output` and `deploy-dry-run` pass in the staged job tree;
  under `wrangler dev` with no Stripe key and no `AUTH_SECRET` the
  component's own smoke passes and a sign-up, the dashboard and a sign-in
  work; 0 of 5 public tables without RLS, and `anon`/`authenticated` read
  and write none of the rows.
- `orun task check SA-7` complete.
