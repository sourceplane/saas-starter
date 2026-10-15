#!/usr/bin/env bash
# A throwaway Postgres for the e2e: the database a Supabase project would be,
# on a random local port, deleted with the scratch directory. Sourced.
#
#   pg_up <dir> <port>    start it in <dir> — a fresh `mktemp -d`, which it
#                         takes over — and print its URL on stdout
#   pg_down <dir>         stop it
#
# Postgres refuses to run as root, so when the caller is root the server runs
# as the `postgres` system user (Debian's packages create one). Trust auth on
# 127.0.0.1 only: the URL's password is ignored, which is what lets the same
# `postgres://postgres:postgres@…` shape the wrangler config uses reach it.
#
# Needs: a PostgreSQL server install (initdb, pg_ctl) — /usr/lib/postgresql/*/bin
# is searched when they are not on PATH.

pg_bin() {
  local b
  if command -v initdb >/dev/null 2>&1; then dirname "$(command -v initdb)"; return; fi
  for b in /usr/lib/postgresql/*/bin; do [ -x "$b/initdb" ] && { echo "$b"; return; }; done
  return 1
}

pg_as() { # run a command as the user that owns the cluster
  if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi
}

pg_up() {
  local dir="$1" port="$2" bin
  bin="$(pg_bin)" || { echo "pg_up: no PostgreSQL server binaries (initdb, pg_ctl)" >&2; return 1; }
  mkdir -p "$dir"
  [ "$(id -u)" = 0 ] && chown postgres "$dir" && chmod 700 "$dir"
  pg_as "$bin/initdb" -D "$dir/data" -U postgres --auth=trust -E UTF8 >"$dir/initdb.log" 2>&1 \
    || { cat "$dir/initdb.log" >&2; return 1; }
  pg_as "$bin/pg_ctl" -D "$dir/data" -l "$dir/server.log" -w -t 60 \
    -o "-p $port -c listen_addresses=127.0.0.1 -k $dir -c fsync=off" start >/dev/null \
    || { cat "$dir/server.log" >&2; return 1; }
  echo "postgres://postgres:postgres@127.0.0.1:$port/postgres"
}

pg_down() {
  local dir="$1" bin
  bin="$(pg_bin)" || return 0
  [ -d "$dir/data" ] && pg_as "$bin/pg_ctl" -D "$dir/data" -m immediate stop >/dev/null 2>&1 || true
}
