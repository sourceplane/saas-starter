# BOOTSTRAP — a new SaaS product from this baseline, in one landing

How to go from **nothing** to **a SaaS product live on stage and prod —
its own Supabase project per environment, Hyperdrive in front of it, the
schema applied, the app deployed — documented**, with two provider consents.

There is one artifact: **`repo-blueprint.yaml`**. It declares what to place,
in what order, what each phase needs first, and what to say while it runs.
`orun new` is the whole runtime — the phases below are its `--phase` names,
not separate workflows. The console card the platform renders is
**`blueprint.yaml`**; it names the build document and states the inputs, the
brokered secrets and the programme, and `testing/manifest.test.sh` holds it
to what the build document does.

Target wall-clock: **about twenty minutes** — an estimate summed from the
phases until a bootstrap measures it: one landing, then one convergence per
environment (stage and prod side by side until `02-docs` restores the
promotion gate) that creates the Supabase project (five to seven minutes),
the Hyperdrive config, applies the migrations and builds and deploys the app,
in that order.

## 0. What you need

- GitHub org access (repository creation) and a machine with `git`, `node`
  (≥ 22), `pnpm` (10.12.1), `python3` with PyYAML, `curl`, and the `orun`
  CLI **≥ v2.58.11** — the floor for RUNNING the bootstrap (the phase overlay,
  landings that wait on the PR's whole CI run, `githubOwner` on the doctor
  probe, `environments` on the secrets probe, `from: workspace`). The
  product's own `ci.yml` pins its lanes separately (v2.78.4), and that pin is
  what reads the per-edge `mode` rules the convergence order relies on.
- A **Cloudflare** account (the free plan is enough for one Worker with
  static assets and Hyperdrive) and its Account API token with the
  permission groups the console's Connect recipe lists — Workers Scripts and
  Hyperdrive among them.
- A **Supabase** organization the platform can create projects in, connected
  to the workspace (console → Integrations → Supabase). Each environment gets
  its own project — mind your plan's project limit.
- An Orun Cloud workspace for the product — `orunWorkspace`, or the workspace
  the build runs in (ORUN_WORKSPACE) when that is unset — with an
  **admin-role API key** for headless runs (secret writes below admin are
  masked as `not_found`).
- **The repository allow-listed in the workspace** (console → Settings → Git
  repos), unless the credential can write links. `01-product`'s `link` step
  stops and names the fix if it is not.
- **Not Stripe.** No platform brokers it: the product deploys without a
  Stripe key and its owner adds one afterwards (§3).

## 1. One command: `--resume`

The whole bootstrap, unattended. `--resume` places every phase not already
derived as done, in order, honouring each phase's barrier:

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/saas-starter
cd saas-starter

orun new --blueprint repo-blueprint.yaml \
  --out ~/products/acme-saas --run-hooks --resume \
  --set reponame=acme-saas --set productname="Acme Cloud" \
  --set productdomain=acme.dev --set githuborg=acme-inc \
  --set orunWorkspace=ws_XXXXXXXX \
  --set subdomain=<workers-dev-subdomain>
```

`subdomain` is the workers.dev subdomain of the Cloudflare account you deploy
into (Workers & Pages → your subdomain). A build started from the console, or
with `orun baseline new --from bst_…`, never asks for it: the platform reads
it from the workspace's Cloudflare connection, the same one the deploy tokens
mint from. Only a hand-run build like this one passes it.

**`--run-hooks` is the difference between placing files and bootstrapping a
product.** Without it `orun new` writes the tree and stops: no repository, no
landing, no convergence watch, no probe. That is deliberate — it is what
makes the offline bootstrap in `testing/` possible with no workspace and no
provider.

`--resume` is safe to re-run from anywhere, a fresh container with a fresh
`--out` included: **phase state is derived from the tree, never stored.** A
phase whose files are present but branded derives as `drifted`, and
`--resume` leaves it placed rather than reverting the product's identity.

## 1b. Or phase by phase

| phase | what it lands | verified by |
|---|---|---|
| `01-product` | the repository, created and linked; the five brokered credentials; then the whole product in one PR — intent, CI, tooling, identity, the Supabase and Hyperdrive Terraform roots, the migrations, the app and its tests | the convergence green (supabase → cloudflare-hyperdrive → db-migrate → web, per environment), the four published secrets on stage and prod, `/` and `/api/health` answering on both workers.dev URLs |
| `02-docs` | `ai/context/deployment.md` from probed facts (Stripe's state included); prod's promotion gate and dev's push lanes restored | the final probe |

```bash
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-saas --run-hooks \
  --phase 01-product --values ~/acme-saas.values.yaml
# … then 02-docs
```

`02-docs` reads the identity back from `.rebrand/values.json` in the placed
tree, but the blueprint's **required** inputs — `reponame`, `productname`,
`productdomain`, `githuborg` — are validated before anything runs, so pass
them every time (a `--values` file is easier). The full guide, one page per
phase: [docs/phases/README.md](docs/phases/README.md).

| flag | what it does |
|---|---|
| `--status` | derives and prints every phase's state and writes nothing. It parses the document, validates each hook against the action registry and compiles every template; it needs no credential and no network |
| `--phase <name>` | places exactly that phase; its `requires.phases` still gates |
| `--until <name>` | places every phase through that one and stops |

What lands in the product is PRODUCT-ONLY: the app, the Terraform roots, the
migrations and their runner, the tests, its CI, its tooling, its README and
its two context pages. None of this repository's machinery (`.baseline/`, the
blueprints, `tooling/rebrand`, `tooling/bootstrap`, `hooks/`, `testing/`,
`docs/phases/`, `specs/`, `tasks/`, this file) ships, and no shipped file
names any of it. That promise is a test: `testing/leak.test.sh` derives what
every phase would place and gates the set and every file's text, and
`testing/placement.test.sh` gates the same rules over a placed, branded tree.

## 2. Headless / container mode

The blueprint's source is this repository (`sources: [{kind: dir, path: .}]`),
so the container contract is a shallow clone at a pinned tag plus two
tokens:

```bash
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (below)

git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/saas-starter
cd saas-starter
orun new --blueprint repo-blueprint.yaml \
  --out /work/acme-saas --run-hooks --resume --progress json \
  --values /work/acme-saas.values.yaml
```

| requirement | detail |
|---|---|
| `GITHUB_TOKEN` | fine-grained PAT: **read** on this repository; on the PRODUCT's repository **contents write**, **pull-requests write**, **actions read+write** (`orun.run/watch@v1` resumes runs with `gh run rerun`), **checks read**; **repository create** on the owner if `01-product` creates it (or pre-create it — supported) |
| classic token caveat | a classic PAT or gh OAuth token also needs the `workflow` scope to push `.github/workflows/` |
| pinning | the clone's `--branch <tag>` pins everything: the blueprint, its modules and its hooks' scripts all come from that one commit |

## 3. After the product is live

- **Connect Stripe** (per environment): create the **Base** and **Plus**
  products with a monthly price each, add the webhook endpoint
  `https://<reponame>-web-<env>.<subdomain>.workers.dev/api/stripe/webhook`
  (`customer.subscription.updated`, `customer.subscription.deleted`), and set
  the Worker secrets:

  ```bash
  wrangler secret put STRIPE_SECRET_KEY     --name <reponame>-web-<env>
  wrangler secret put STRIPE_WEBHOOK_SECRET --name <reponame>-web-<env>
  ```

  Until then the pricing page says "Connect Stripe to enable checkout",
  checkout and the portal send visitors there and the webhook answers 503 —
  sign-up, sign-in and the dashboard work either way. The product's README,
  "Connect Stripe", is the owner's copy of this.
- **The session key** needs nothing: the database generated one per
  environment when the migrations first ran. `AUTH_SECRET` as a Worker secret
  overrides it (and ends every session).
- **Custom domain**: attach it to the Worker in Cloudflare, then set
  `BASE_URL` in the product's `apps/web/wrangler.template.jsonc` (its README,
  "Custom domain"). There is no domain phase: attaching a domain needs zone
  permissions the brokered `workers-deploy` token does not carry.
- **Refresh the record**: re-run `--phase 02-docs`; it is idempotent, and it
  records whether Stripe is connected.

## 4. Testing this baseline

`.github/workflows/baseline.yml` runs three tiers on every pull request, and
each runs locally the same way:

```bash
for t in manifest phases coverage rebrand retouch bootstrap-defer; do bash testing/$t.test.sh; done
bash testing/leak.test.sh        # needs orun
bash testing/placement.test.sh   # needs orun, node, pnpm: the offline bootstrap and the product's own plans
bash testing/e2e.test.sh         # + network for pnpm, psql and a PostgreSQL server install
```

The offline bootstrap (`testing/lib/bootstrap.sh`) places both phases in
order and finishes each with the blueprint's OWN `run:` hooks — read out of
`repo-blueprint.yaml`, not transcribed — so the retouch marker, the rebrand,
the re-tenant, the deferrals and their restore, the lockfile and the
deployment record all run exactly as a real bootstrap runs them. Only the
platform's typed actions (task, repo, reconcile, land, watch, secrets,
probe) and the `link` step are stood in for, a landing becoming a commit.

What no test here can do is the clouds' half: create a Supabase project,
apply the Hyperdrive config, mint a token, deploy for real. The Terraform
roots are held to `fmt`, `init -backend=false` and `validate` (a real `plan`
reads Supabase's API and the platform's state backend); the convergence
ORDER is proven on the product's own `orun plan`; and the migrations are
applied by the product's own runner to a local Postgres through a stand-in
for the one Supabase Management API endpoint it calls
(`testing/lib/fake-supabase-api.py`), before the built Worker serves a
sign-up over that database.

## 5. Cutting a baseline tag (maintainers)

Every product built from this repository resolves a `baseline-vN` tag, so the
tag is cut by a workflow rather than by hand:

```bash
gh workflow run tag.yml -f version=baseline-v1          # from main
gh workflow run tag.yml -f version=baseline-v1 -f ref=<sha>
```

It refuses a version that is not `baseline-v<N>` and a tag that already
exists: a baseline tag is never moved. Then add (or move) the registry row in
orun-cloud's `infra/baselines-registry/baselines.yaml` by pull request —
after the tag exists, because the registry's sync fetches `blueprint.yaml`
at the tag and refuses the whole catalogue if it 404s.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `01-product` parks: `waiting for github for <org>` | the workspace's GitHub connection is to another account. Connect the App installation on `<org>` (console → Integrations → GitHub), then `--resume` |
| `01-product` parks on the `providers` probe for cloudflare or supabase | that connection is missing. Connect it (console → Integrations); the probe is a wait, not a failure |
| `01-product` stops at `link` | the repository is not linked to the workspace and the credential cannot link it. Allow-list it (console → Settings → Git repos) and re-run the phase |
| Secret WRITE fails `not_found` while listings work | the API key's role is below admin; re-mint it with the admin role |
| supabase apply: `does not support oauth access` | a supabase provider ≥ 1.6 reads billing endpoints the brokered OAuth token cannot; the root pins `~> 1.5.1` — keep it |
| supabase apply: project limit reached | the Supabase org's plan allows fewer projects than stage + prod need; free one or upgrade, then re-run `01-product` |
| hyperdrive apply: Authentication error (10000) | the Hyperdrive token lacks the permission; reconnect Cloudflare with the recipe's permission groups and re-run the phase — the reconcile re-mints only what is missing |
| hyperdrive or db-migrate: `secret resolution failed … SUPABASE_*` | the supabase apply for that environment did not publish; its lane's log says why. Both wait on it, enforced |
| db-migrate: `row-level security would lock the app out of …` | migration 030 refused: `postgres` (Hyperdrive's role) neither owns the tables in `public` nor bypasses RLS. Nothing was enabled; give `postgres` the tables or BYPASSRLS and re-run `01-product` |
| web smoke: `/api/health` 503 | `database: unreachable` — the Hyperdrive config is wrong or the project is paused; `schema: missing` — db-migrate did not run for that environment |
| `build-app` fails: `Symlink apps/web/node_modules/next is invalid, it points out of the filesystem root` | the product's intent pins stack-tectonic ≥ 0.20.0, whose lane-scoped install links each job's node_modules out of its tree, which Next 16's Turbopack refuses. Pin 0.19.0 (`intent.yaml` says why) |
| `verify-app-structure` fails: `test -f "wrangler.jsonc"` | the product's `apps/web/wrangler.jsonc` is not committed. It must be — the check runs before the build in a fresh checkout (`pnpm run wire:fixture` renders it) |
| Convergence failed AFTER the PR merged; re-running lands nothing | expected on its own — the files are on main. Re-run the phase (`--phase 01-product`, `--redo 01-product`, or the console's Retry): its `retouch` hook gives the landing a diff and the components re-plan; the project and the config are adopted, not recreated |
| The convergence reported green, then `verify` got 404 | a second workflow ran on the push to main and the watch took its run. Only `ci.yml` may run on a push to main; `checks.yml` runs on pull requests only |
| The product's `intent.yaml` says `workspace: ws_SET_ME` | `orunWorkspace` was empty and the build ran outside a workspace; set it and re-run `01-product` |
| A bootstrap stopped before `02-docs`; prod no longer waits on stage | the gate is deferred, not dropped: run `02-docs`, or `node tooling/bootstrap/promotion.mjs --restore --file <product>/intent.yaml` |
| `✕ input "productdomain" is required` | all four required inputs must be set on every invocation, single-phase ones included |
| `unknown flag: --phase` or a parse error in the blueprint | the CLI is below the v2.58.11 floor |
