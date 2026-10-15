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
