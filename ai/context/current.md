# saas-starter — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it;
the two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Vercel's Next.js SaaS Starter — Postgres through Drizzle, Stripe Checkout,
the Customer Portal and webhooks, email/password auth with a JWT cookie,
teams with roles, invitations and an activity log — on Cloudflare Workers +
Static Assets (through `@opennextjs/cloudflare`), its Postgres a Supabase
project's database reached through Cloudflare Hyperdrive, both from
Terraform, and its schema applied by db-migrate. It is packaged as an Orun
baseline: `orun new --blueprint repo-blueprint.yaml` builds a new product in
its own repository and takes it to live on stage and prod in one landing
(`01-product`: the Supabase project, then Hyperdrive over its database, then
the migrations, then the app), then records what went live (`02-docs`).
Stripe is the owner's to connect afterwards; the app deploys, signs users up
and serves without it.

## Release

| | |
|---|---|
| Latest tag | `baseline-v3` (SA7, [#8](https://github.com/sourceplane/saas-starter/pull/8) — the domain is set later: the console asks for no domain, and a product is born with the placeholder `<reponame>.example.com` in `BASE_DOMAIN` for an owner to replace) |
| Before it | `baseline-v2` (SA6, [#7](https://github.com/sourceplane/saas-starter/pull/7) — the cirrus standard: no kiox, generated component docs, this context pack, and the workers.dev subdomain read from the Cloudflare connection instead of asked); `baseline-v1` (SA5, [#6](https://github.com/sourceplane/saas-starter/pull/6) — the baseline) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI: the e2e tier migrates a local Postgres with the product's own runner, builds in orun's staged job tree, and signs a user up and in with no Stripe key and no `AUTH_SECRET`. No bootstrap from a tag has run against a workspace: neither Terraform root has been applied, db-migrate has not run against a real project, nothing has deployed, and the card's eighteen minutes is unmeasured (SA-M) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/saas-starter/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/saas-starter/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/saas-starter/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `<component>/docs/` beside each `component.yaml` — `apps/web`, `packages/db`, `infra/db-migrate`, `infra/terraform/{supabase,cloudflare-hyperdrive}`, `tests/{web,db}` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one product from `baseline-v3` against a workspace with
   Cloudflare and Supabase connected, and record its timings (closes SA-M;
   settles SA-L's table-owner check on a real project).
