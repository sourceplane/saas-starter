# saas-starter — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | OpenNext on Workers + Static Assets (Next 16.3.8, React 19) | `@opennextjs/cloudflare` needs a current Next; only what Next 16 and Workers force changes in the template | epic README (decisions locked), IMPLEMENTATION-STATUS (Versions) |
| 2 | Drizzle over a Postgres socket through Hyperdrive — not PostgREST, not D1 | The template's data access is SQL; Hyperdrive gives the Worker the socket the code already expects | design.md §6 |
| 3 | A `postgres` client per request (`getDb()` in `lib/db/drizzle.ts`), never a module-level pool | Workers refuse to reuse a socket another request opened; Hyperdrive is the pool | design.md §3, risk SA-A |
| 4 | `apps/web/wrangler.jsonc` is committed as the fixture render; stage and prod re-render it from `WIRING_CLOUDFLARE_HYPERDRIVE` | The composition checks the file exists before the build, in a fresh checkout | risk SA-K |
| 5 | The schema is applied by the `@saas/db` runner (db-migrate) through Supabase's Management API, from the drizzle-kit SQL; drizzle-kit stays for local development | The token is already brokered; no CLI binary and no direct Postgres connection on the runner | design.md §2, risk SA-E |
| 6 | A fresh product needs no hand-set secret: Stripe is optional (pricing says checkout is not connected, the webhook answers 503), and the session key defaults to one the database generates (`020_app_secrets`) unless `AUTH_SECRET` is set | A bootstrapped product is deployed by a convergence nobody attends, and no platform brokers Stripe | risk SA-J |
| 7 | Row-level security with no policy on every table in `public`; migration `030` refuses to run if `postgres` would be locked out | Supabase's Data API serves `public` to the anon key; the app connects as the tables' owner | risk SA-L |
| 8 | Infra before app on main: supabase → cloudflare-hyperdrive → db-migrate → web, enforced; advisory on a pull request | Each component reads what the one before it published; a migration is the one step a re-run cannot take back, so it runs last before the Worker | design.md §4, IMPLEMENTATION-STATUS (SA5) |
| 9 | One landing (`01-product`) then the record (`02-docs`); `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME`; `checks.yml` on pull requests only | A landing has a fixed cost; a bootstrap cannot set a repository variable (replaced the `ORUN_CI` gate); a push to main must start `ci.yml` alone | `repo-blueprint.yaml`, IMPLEMENTATION-STATUS (SA5) |
| 10 | stack-tectonic 0.19.0, not 0.20.0 | 0.20.0's lane-scoped install is refused by Turbopack | `intent.yaml`, IMPLEMENTATION-STATUS (SA5) |
| 11 | orun is pinned only where it runs (the `orun-action` `version:` in each workflow); no kiox | `kiox.yaml` pinned a version (v2.15.0) nothing ran | IMPLEMENTATION-STATUS (SA6) |
| 12 | Component docs are generated from the manifests and checked in CI | A hand-written copy of the dependency graph and bindings drifts silently | `tooling/catalog/gen-component-docs.py` |
| 13 | `subdomain` is read from the Cloudflare connection (`from: connection.cloudflare.workersSubdomain`), never asked | It belongs to the account like its id and has one right answer; a typed one could only be wrong, and showed up after deploy in `BASE_URL`, the smoke and the probes | `blueprint.yaml`, IMPLEMENTATION-STATUS (SA-8) |
