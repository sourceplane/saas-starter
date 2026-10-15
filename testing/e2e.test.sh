#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, migrates, deploys (dry),
# serves, and signs a user up, with no Stripe key and no AUTH_SECRET.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree,
# and that its own plan converges in the right order. This proves it WORKS,
# by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its PR merges), run what
#      `checks.yml` runs on that PR — install with the lockfile the phase
#      placed, render the wrangler fixture (which must change nothing: the
#      render is committed), typecheck, lint, test, build. That landing WAITS
#      on its checks;
#   2. a Postgres of its own on a random port — the database a Supabase
#      project would be — and a stand-in for the ONE Supabase Management API
#      endpoint the migration runner calls (testing/lib/fake-supabase-api.py);
#   3. the db-migrate lane's own steps, rendered by `orun plan` for a push to
#      main and run IN THE TREE THE RUNNER STAGES for the job: install, build
#      @saas/db, apply — every migration, the session key the database
#      generates for itself included — then apply again, which must apply
#      nothing, and the pull-request profile's offline plan;
#   4. the web lane's own steps for stage, rendered for a pull request (the
#      verify profile carries deploy-dry-run; the deploy profile does not) and
#      run in its staged job tree: install, `verify-app-structure` (the
#      committed wrangler.jsonc must exist BEFORE the build, in a tree with no
#      build output), `build-app` — which re-renders the config from the
#      stage wiring document it is handed, as the deploy does — then
#      `verify-build-output` and `deploy-dry-run`;
#   5. the built Worker under `wrangler dev`, its HYPERDRIVE binding pointed at
#      that Postgres, with NO .dev.vars — no Stripe key, no AUTH_SECRET — and
#      the component's OWN `smokeCommand` against it, verbatim; then every
#      route the product promises: the pages carry the product's name, the
#      pricing page says Stripe is not connected (not a 500), the Stripe routes
#      degrade, `/api/health` and `/api/user` (answered only by the Worker)
#      answer, and a visitor signs up, lands on the dashboard, signs in again
#      — the session signed with the key the database generated.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered tokens, create a real Supabase project and Hyperdrive config
# (Terraform is validated, not applied, in this repository), deploy for real
# and probe workers.dev. That is a bootstrap against a workspace
# (BOOTSTRAP.md); everything short of it is here.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, psql and a
# PostgreSQL server install (initdb, pg_ctl), and the network for
# `pnpm install` (or a warm store). A few minutes: three installs, two builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"
# shellcheck source=lib/local-postgres.sh
source "$here/lib/local-postgres.sh"

for bin in orun node pnpm python3 git curl psql; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done
pg_bin >/dev/null || { echo "e2e.test.sh needs a PostgreSQL server install (initdb, pg_ctl)" >&2; exit 1; }

scratch="$(mktemp -d)"
pgdir="$(mktemp -d)"
dev_pid=""
api_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So each
# server is started as its own process group (setsid) and the group stopped.
stop_group() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$pid" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$pid" 2>/dev/null || true
}
cleanup() {
  stop_group "$dev_pid"
  stop_group "$api_pid"
  pg_down "$pgdir"
  [ -n "$pgdir" ] && [ -d "$pgdir" ] && rm -rf "$pgdir"
  [ -n "$scratch" ] && [ -d "$scratch" ] && rm -rf "$scratch"
}
trap cleanup EXIT
free_port() { python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"; }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false NEXT_TELEMETRY_DISABLED=1 TURBO_TELEMETRY_DISABLED=1

# What checks.yml runs, step for step, read out of the workflow the product
# carries so the two cannot drift: every `run:` of its one job, in order.
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  while IFS= read -r cmd; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done < <(python3 - "$dir/.github/workflows/checks.yml" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for job in wf["jobs"].values():
    for step in job["steps"]:
        if "run" in step:
            print(step["run"].strip())
PY
)
}

# One job of a plan, written out as the runner would run it: each `run:` step
# (the `use:` actions are setup-node and setup-pnpm, which this machine has)
# as a numbered script, the job's env, and the component path the steps run
# in. Steps are picked BY ID when given, else every `run:` step in order.
extract_job() { # PLAN JOB-ID OUT-DIR [STEP-ID…]
  python3 - "$@" <<'PY'
import json, pathlib, sys
plan, jid, out, *want = sys.argv[1:]
job = next((j for j in json.load(open(plan))["jobs"] if j["id"] == jid), None)
if job is None:
    sys.exit(f"the plan has no job {jid}")
out = pathlib.Path(out); out.mkdir(parents=True)
steps = [s for s in job["steps"] if s.get("run")]
if want:
    by = {s["id"]: s for s in steps}
    missing = [w for w in want if w not in by]
    if missing:
        sys.exit(f"{jid} has no step(s) {missing}")
    steps = [by[w] for w in want]
for i, s in enumerate(steps):
    (out / f"{i:02d}.sh").write_text(s["run"])
    (out / f"{i:02d}.id").write_text(s["id"])
(out / "path").write_text(job.get("path") or ".")
with (out / "env").open("w") as f:
    for k, v in (job.get("env") or {}).items():
        f.write(f"export {k}={json.dumps(v)}\n")
PY
}
run_job() { # STEPS-DIR WORK-TREE ENV LOG-PREFIX
  local steps="$1" work="$2" envname="$3" logp="$4" s id
  for s in "$steps"/[0-9][0-9].sh; do
    id="$(cat "${s%.sh}.id")"
    echo "   ▸ $id"
    if ! (cd "$work/$(cat "$steps/path")" && source "$steps/env" && export ORUN_ENVIRONMENT="$envname" \
          && bash -e "$s") > "$logp-$id.log" 2>&1; then
      echo "FAIL: the lane's $id step" >&2; tail -40 "$logp-$id.log" >&2; return 1
    fi
  done
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"

# ── 1. the product's own pull request ──────────────────────────────────────
echo "── 01-product's landing, under the checks its PR waits on"
s01="$(git -C "$tree" rev-parse HEAD~1)"
at01="$scratch/at-01/$repo"
git -C "$tree" worktree add -q "$at01" "$s01"
checks "$at01" "$scratch/checks.log"
dirty="$(git -C "$at01" status --porcelain)"
[ -z "$dirty" ] || { echo "FAIL: the checks changed tracked files — the committed wrangler.jsonc is not the fixture render:" >&2; echo "$dirty" >&2; exit 1; }
echo "   the checks left the tree as committed (wire:fixture rendered the committed wrangler.jsonc)"

# ── 2. a database, and the one API the migration runner calls ──────────────
echo "── a local Postgres and the Supabase Management API stand-in"
pgurl="$(pg_up "$pgdir" "$(free_port)")" || { echo "FAIL: Postgres did not start" >&2; exit 1; }
api_port="$(free_port)"
ref="localproject"
setsid python3 "$here/lib/fake-supabase-api.py" "$api_port" "$pgurl" --ref "$ref" > "$scratch/api.log" 2>&1 < /dev/null &
api_pid=$!
for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$api_port/" && break; sleep 0.3; done
echo "   $pgurl; the API on :$api_port"

# The two plans the lanes below run from, each in the product's own tree: a
# push to main at the 01-product commit (the db-migrate lane's APPLY profile),
# and a pull request over the finished product against an empty base (the web
# lane's VERIFY profile, which carries deploy-dry-run, and db-migrate's PLAN).
(cd "$at01" && orun plan --intent intent.yaml --trigger github-push-main --env stage --output "$scratch/plan-main.json") > "$scratch/plan-main.log" 2>&1 \
  || { echo "FAIL: orun plan (push to main)" >&2; tail -15 "$scratch/plan-main.log" >&2; exit 1; }
git -C "$tree" worktree remove --force "$at01"
mkdir -p "$scratch/pr"
git clone -q "$tree" "$scratch/pr/$repo"
prtree="$scratch/pr/$repo"
git -C "$prtree" checkout -q --orphan empty
git -C "$prtree" rm -rqf .
git -C "$prtree" -c user.email=t@example.invalid -c user.name=t commit -qm empty --allow-empty
git -C "$prtree" checkout -q main
(cd "$prtree" && orun plan --intent intent.yaml --trigger github-pull-request --base empty --head HEAD --env stage \
   --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan-pr.log" >&2; exit 1; }
# This tier runs the orun the product's CI pins, which reads the per-edge
# `modeRules`: on a pull request — which applies and deploys nothing — the
# infrastructure edges that order a push to main are advisory, so no lane
# waits on another. (placement.test.sh checks the push to main's order.)
python3 - "$scratch/plan-pr.json" <<'PY'
import json, sys
jobs = {j["component"]: j for j in json.load(open(sys.argv[1]))["jobs"] if j["environment"] == "stage"}
chain = ["supabase", "cloudflare-hyperdrive", "db-migrate", "web"]
for a, b in zip(chain, chain[1:]):
    ja, jb = jobs[a], jobs[b]
    if ja["id"] in (jb.get("dependsOn") or []) or ja["id"] not in (jb.get("advisoryDependsOn") or []):
        sys.exit(f"FAIL: on a pull request {b}@stage must name {a}@stage as advisory, not wait on it")
print("   pull request: " + " → ".join(chain) + ", every edge advisory")
PY

# ── 3. the db-migrate lane, in its staged job tree ─────────────────────────
echo "── the stage db-migrate lane: install, build @saas/db, apply — then apply again, and the PR's plan"
extract_job "$scratch/plan-main.json" db-migrate.stage.migrate "$scratch/steps-migrate" \
  install-dependencies build-db-package "Migration Apply"
extract_job "$scratch/plan-main.json" db-migrate.stage.migrate "$scratch/steps-migrate-again" "Migration Apply"
extract_job "$scratch/plan-pr.json" db-migrate.stage.migrate "$scratch/steps-migrate-plan" "Migration Plan"
# Staged from the fresh clone (a CI checkout: no build output, no
# node_modules); its migrations are the 01-product commit's, byte for byte.
mwork="$prtree/.orun/runs/e2e/db-migrate.stage.migrate/work"
python3 "$here/lib/stage-job.py" "$prtree" "$mwork"
# The component's secretEnv, as the lane resolves it: the supabase apply's
# published credentials and the brokered access token. SUPABASE_API_URL is
# the one value no lane has — it points the runner at the stand-in.
export SUPABASE_ACCESS_TOKEN=e2e-token SUPABASE_PROJECT_REF="$ref" SUPABASE_DB_PASSWORD=postgres \
       SUPABASE_DB_URL="$pgurl" SUPABASE_API_URL="http://127.0.0.1:$api_port"
run_job "$scratch/steps-migrate" "$mwork" stage "$scratch/migrate"
applied() { python3 -c "import json,sys;t=open(sys.argv[1]).read();print(' '.join(json.loads(t[t.index('{'):t.rindex('}')+1])['applied']))" "$1"; }
want="000_control_baseline 010_saas_starter_schema 020_app_secrets"
[ "$(applied "$scratch/migrate-Migration Apply.log")" = "$want" ] \
  || { echo "FAIL: the first apply applied '$(applied "$scratch/migrate-Migration Apply.log")', not '$want'" >&2; exit 1; }
echo "   applied $want"
run_job "$scratch/steps-migrate-again" "$mwork" stage "$scratch/migrate-again"
[ -z "$(applied "$scratch/migrate-again-Migration Apply.log")" ] \
  || { echo "FAIL: a second apply applied '$(applied "$scratch/migrate-again-Migration Apply.log")'" >&2; exit 1; }
echo "   a second apply applied nothing (the ledger holds $(psql "$pgurl" -XAtc 'select count(*) from _migrations.applied') migrations)"
key_len="$(psql "$pgurl" -XAtc "select length(value) from app_private.secrets where name = 'auth_secret'")"
[ "$key_len" = 64 ] || { echo "FAIL: the database generated no 64-character session key (got '$key_len')" >&2; exit 1; }
echo "   the database generated its own session key (64 hex characters)"
run_job "$scratch/steps-migrate-plan" "$mwork" stage "$scratch/migrate-plan"
[ "$(applied "$scratch/migrate-plan-Migration Plan.log")" = "$want" ] \
  || { echo "FAIL: the pull request's offline plan did not verify every migration" >&2; exit 1; }
echo "   the pull request's plan step verifies every migration's checksum offline"
unset SUPABASE_ACCESS_TOKEN SUPABASE_PROJECT_REF SUPABASE_DB_PASSWORD SUPABASE_DB_URL SUPABASE_API_URL
rm -rf "$mwork"

# ── 4. the web lane's steps, for stage ─────────────────────────────────────
echo "── the stage web lane: install, verify-app-structure, build-app, verify-build-output, deploy-dry-run"
extract_job "$scratch/plan-pr.json" web.stage.verify-deploy "$scratch/steps-web" \
  install-workspace-dependencies verify-app-structure build-app verify-build-output deploy-dry-run
work="$prtree/.orun/runs/e2e/web.stage.verify-deploy/work"
# The job's private tree, staged as orun stages it — no build output, no
# node_modules: under stack-tectonic 0.19.0 the job installs inside it.
python3 "$here/lib/stage-job.py" "$prtree" "$work"
[ ! -e "$work/apps/web/.open-next" ] && [ -f "$work/apps/web/wrangler.jsonc" ] \
  || { echo "FAIL: the staged tree is not a fresh checkout with the committed wrangler.jsonc" >&2; exit 1; }
echo "   staged: $(realpath --relative-to="$prtree" "$work") — no build output, the committed wrangler.jsonc"
# The stage wiring document, as the cloudflare-hyperdrive apply publishes it
# and the lane resolves it (secretEnv WIRING_CLOUDFLARE_HYPERDRIVE_STAGE).
hd_id="e2e0000000000000000000000000c0de"
export WIRING_CLOUDFLARE_HYPERDRIVE_STAGE="{\"hyperdrive_id\":\"$hd_id\",\"hyperdrive_name\":\"stg-$repo-stage\"}"
run_job "$scratch/steps-web" "$work" stage "$scratch/web"
unset WIRING_CLOUDFLARE_HYPERDRIVE_STAGE
build_log="$(ls "$scratch"/web-build-app.log)"
grep -q '(Turbopack)' "$build_log" \
  || { echo "FAIL: the staged build did not run on Turbopack" >&2; grep -m3 'Next.js' "$build_log" >&2; exit 1; }
grep -q "\"id\": \"$hd_id\"" "$work/apps/web/wrangler.jsonc" \
  || { echo "FAIL: build-app did not re-render wrangler.jsonc from the stage wiring document" >&2; exit 1; }
[ "$(node -e 'const fs=require("fs");process.stdout.write(String(fs.readdirSync(process.argv[1]).length))' "$work/node_modules")" -gt 0 ] && [ ! -L "$work/node_modules" ] \
  || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
echo "   the staged build ran on Turbopack, inside its own tree, bound to the stage Hyperdrive id it was handed"

# ── 5. serve it with no Stripe key and no AUTH_SECRET ──────────────────────
echo "── wrangler dev over the built Worker, its HYPERDRIVE binding on the local Postgres"
[ ! -e "$work/apps/web/.dev.vars" ] || { echo "FAIL: the staged tree carries a .dev.vars" >&2; exit 1; }
port="$(free_port)"
(cd "$work/apps/web" && CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE="$pgurl" \
   exec setsid pnpm exec wrangler dev --config wrangler.jsonc --ip 127.0.0.1 --port "$port" \
   --name "$repo-web-stage" --show-interactive-dev-session=false) > "$scratch/dev.log" 2>&1 < /dev/null &
dev_pid=$!
url="http://127.0.0.1:$port"
for _ in $(seq 1 90); do
  curl -s -o /dev/null "$url/" && break
  kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
  sleep 1
done
curl -s -o /dev/null "$url/" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the product" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ every route the product promises, and a user signing up"
python3 - "$url" "$values" "$pgurl" <<'PY' || { echo "FAIL: the routes; wrangler dev said:" >&2; tail -40 "$scratch/dev.log" >&2; exit 1; }
import base64, hashlib, hmac, html, json, re, subprocess, sys, urllib.error, urllib.request, uuid
base, values, pgurl = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3]
name = values["productname"]
problems = []
def bad(m): problems.append(m)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k): return None
opener = urllib.request.build_opener(NoRedirect)
import http.client, time
def req(path, data=None, headers=None, method=None):
    # A GET whose CONNECTION drops (not one that answers an error) is asked
    # again, twice at most, and says so: `wrangler dev` on a loaded machine
    # has dropped one. A POST is never repeated — it would submit twice.
    for attempt in range(3):
        r = urllib.request.Request(base + path, data=data, headers=headers or {}, method=method)
        try:
            with opener.open(r, timeout=60) as resp:
                return resp.status, {k.lower(): v for k, v in resp.headers.items()}, resp.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read().decode()
        except (http.client.RemoteDisconnected, ConnectionResetError) as e:
            if data is not None or attempt == 2:
                raise
            print(f"   (GET {path}: the connection dropped ({e.__class__.__name__}) — asking again)")
            time.sleep(1)
def location(h):
    return urllib.parse.urlparse(h.get("location", "")).path
import urllib.parse

# A form as a browser without JavaScript submits it: the hidden fields React
# renders for a server action, multipart, to the page's own URL.
def submit(path, form_html, fields, cookie=None):
    data = {html.unescape(n): html.unescape(v or "") for n, v in
            re.findall(r'<input type="hidden" name="([^"]+)"(?: value="([^"]*)")?', form_html)}
    data.update(fields)
    b = uuid.uuid4().hex
    body = "".join(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n' for k, v in data.items()) + f"--{b}--\r\n"
    h = {"content-type": f"multipart/form-data; boundary={b}", "origin": base}
    if cookie:
        h["cookie"] = cookie
    return req(path, body.encode(), h, "POST")
def forms(page):
    return re.findall(r"<form[^>]*>(.*?)</form>", page, re.S)
def text(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()

# ── the public pages, under the product's own name ────────────────────────
s, _, home = req("/")
if s != 200:
    bad(f"/ answered {s}")
title = re.search(r"<title>(.*?)</title>", home, re.S)
if not title or html.unescape(title.group(1)) != name:
    bad(f"the home page's <title> is {title and title.group(1)!r}, not {name!r}")
if name not in [text(m) for m in re.findall(r'<span class="ml-2 text-xl[^"]*">(.*?)</span>', home, re.S)]:
    bad(f"the header beside the logo does not read {name!r}")
if ">ACME<" in home:
    bad("the home page still carries the baseline's name")
for upstream in ('href="https://github.com/nextjs/saas-starter"',
                 'href="https://vercel.com/templates/next.js/next-js-saas-starter"'):
    if upstream not in home:
        bad(f"the marketing page's upstream link was renamed: {upstream} is gone")

s, _, pricing = req("/pricing")
if s != 200:
    bad(f"/pricing answered {s} — without Stripe it must render, not fail")
if 'data-stripe="not-connected"' not in pricing or "Connect Stripe to enable checkout." not in pricing:
    bad("/pricing does not say Stripe is not connected")
buttons = re.findall(r'<button[^>]*type="submit"[^>]*>', pricing)
if len(buttons) != 2 or not all("disabled" in b for b in buttons):
    bad(f"/pricing's two checkout buttons are not disabled: {buttons}")
for plan in ("Base", "Plus"):
    if f">{plan}<" not in pricing:
        bad(f"/pricing does not show the {plan} plan")

for path, want in (("/sign-in", 200), ("/sign-up", 200), ("/no-such-page", 404)):
    s, _, _ = req(path)
    if s != want:
        bad(f"{path} answered {s}, want {want}")
s, h, _ = req("/dashboard")
if s != 307 or location(h) != "/sign-in":
    bad(f"/dashboard signed out answered {s} → {h.get('location')}, not 307 → /sign-in")

# ── what only the Worker answers ──────────────────────────────────────────
s, _, body = req("/api/health")
if s != 200 or json.loads(body) != {"ok": True, "database": "reachable", "schema": "migrated"}:
    bad(f"/api/health answered {s} {body}")
s, _, body = req("/api/user")
if s != 200 or body.strip() != "null":
    bad(f"/api/user signed out answered {s} {body[:80]}")
s, _, body = req("/api/stripe/webhook", b'{"id":"evt_1"}', {"stripe-signature": "t=1,v1=x"}, "POST")
if s != 503 or json.loads(body) != {"error": "Stripe is not connected."}:
    bad(f"the Stripe webhook answered {s} {body[:80]}, not 503 'Stripe is not connected.'")
s, h, _ = req("/api/stripe/checkout?session_id=cs_test_1")
if s != 307 or location(h) != "/pricing":
    bad(f"the checkout callback answered {s} → {h.get('location')}, not → /pricing")

# ── a visitor signs up, with no AUTH_SECRET anywhere ──────────────────────
email, password = "sam@seats.example", "correct horse battery"
s, _, page = req("/sign-up")
s, h, body = submit("/sign-up", forms(page)[0], {"email": email, "password": password})
cookie = (h.get("set-cookie") or "").split(";")[0]
if s != 303 or location(h) != "/dashboard" or not cookie.startswith("session="):
    bad(f"sign-up answered {s} → {h.get('location')} with cookie {cookie[:20]!r}: {text(body)[:120]}")
else:
    # The session is signed with the key the database generated for itself.
    token = cookie.split("=", 1)[1]
    key = subprocess.run(["psql", pgurl, "-XAtc", "select value from app_private.secrets where name = 'auth_secret'"],
                         capture_output=True, text=True, check=True).stdout.strip()
    signing_input, sig = token.rsplit(".", 1)
    want_sig = base64.urlsafe_b64encode(hmac.new(key.encode(), signing_input.encode(), hashlib.sha256).digest()).rstrip(b"=").decode()
    if not hmac.compare_digest(sig, want_sig):
        bad("the session cookie is not signed with the database's own key")
    s, _, dash = req("/dashboard", headers={"cookie": cookie})
    if s != 200 or "Team Members" not in dash or email not in dash:
        bad(f"/dashboard signed in answered {s}, without the team and the user")
    s, _, activity = req("/dashboard/activity", headers={"cookie": cookie})
    if s != 200 or "You signed up" not in activity:
        bad(f"/dashboard/activity answered {s} without the sign-up")
    s, _, body = req("/api/user", headers={"cookie": cookie})
    if s != 200 or json.loads(body).get("email") != email:
        bad(f"/api/user signed in answered {s} {body[:80]}")
    # Checkout and the customer portal, posted directly (their buttons are
    # disabled): both send the visitor to the pricing notice, not a 500.
    s, _, page = req("/pricing", headers={"cookie": cookie})
    s, h, body = submit("/pricing", forms(page)[0], {}, cookie)
    if s != 303 or location(h) != "/pricing":
        bad(f"checkout without Stripe answered {s} → {h.get('location')}, not → /pricing")
    portal = [f for f in forms(dash) if "$ACTION_ID_" in f and 'name="email"' not in f]
    if not portal:
        bad("the dashboard has no Manage Subscription form")
    else:
        s, h, body = submit("/dashboard", portal[0], {}, cookie)
        if s != 303 or location(h) != "/pricing":
            bad(f"the customer portal without Stripe answered {s} → {h.get('location')}, not → /pricing")

# ── and signs in again ────────────────────────────────────────────────────
s, _, page = req("/sign-in")
s, h, body = submit("/sign-in", forms(page)[0], {"email": email, "password": "not the password"})
if s != 200 or "Invalid email or password" not in body:
    bad(f"a wrong password answered {s}, not the form with its error")
s, h, body = submit("/sign-in", forms(page)[0], {"email": email, "password": password})
if s != 303 or location(h) != "/dashboard" or not (h.get("set-cookie") or "").startswith("session="):
    bad(f"sign-in answered {s} → {h.get('location')}")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   /, /pricing (Stripe not connected), /sign-in, /sign-up, a 404, /dashboard guarded; "
      f"/api/health, /api/user, the Stripe routes degraded; a sign-up, the dashboard, the activity "
      f"log, a sign-in — as {name!r}, signed with the database's own key")
PY

echo "e2e.test.sh: ok"
