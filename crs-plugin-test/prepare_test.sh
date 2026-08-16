#!/usr/bin/env bash
# Self-check for prepare.sh.
# Run: ./test-plugin/prepare_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
prepare="$here/prepare.sh"
compose="$here/docker-compose.yml"
failures=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Builds a workspace that looks like a checked out plugin repository.
# Pass "no-plugins" or "no-crs" to leave that part out. Sets: ws, status, stderr_file.
make_workspace() {
  local name=$1 omit=${2-}
  ws="$workdir/$name"
  mkdir -p "$ws"
  [ "$omit" = "no-plugins" ] || mkdir -p "$ws/plugins"
  if [ "$omit" != "no-crs" ]; then
    mkdir -p "$ws/crs/rules"
    echo "# crs setup" >"$ws/crs/crs-setup.conf.example"
  fi
  stderr_file="$ws.stderr"
}

run_prepare() {
  (cd "$ws" && "$prepare" "$@") >/dev/null 2>"$stderr_file"
  status=$?
}

# --- lays out the workspace for apache
make_workspace apache
run_prepare apache "$compose" ''
[ "$status" -eq 0 ] || fail "apache: want exit 0, got $status"
[ -f "$ws/tests/integration/docker-compose.yml" ] || fail "apache: compose file not copied"
[ -d "$ws/tests/logs/apache" ] || fail "apache: log directory not created"
cmp -s "$compose" "$ws/tests/integration/docker-compose.yml" || fail "apache: compose file was altered in transit"

# --- the log directory is writable by the container's user
[ -n "$(find "$ws/tests/logs/apache" -maxdepth 0 -perm -o+w)" ] \
  || fail "apache: log directory is not world writable, the container cannot write to it"

# --- and for nginx, under its own log directory
make_workspace nginx
run_prepare nginx "$compose" ''
[ "$status" -eq 0 ] || fail "nginx: want exit 0, got $status"
[ -d "$ws/tests/logs/nginx" ] || fail "nginx: log directory not created"
[ ! -d "$ws/tests/logs/apache" ] || fail "nginx: created the apache log directory too"

# --- an unknown backend fails before touching anything
make_workspace bogus
run_prepare iis "$compose" ''
[ "$status" -eq 1 ] || fail "bogus-backend: want exit 1, got $status"
grep -q 'expected apache or nginx' "$stderr_file" || fail "bogus-backend: unhelpful error"
[ ! -d "$ws/tests" ] || fail "bogus-backend: should not have created anything"

# --- a workspace with no plugins/ fails with a pointed message
make_workspace no-plugins no-plugins
run_prepare apache "$compose" ''
[ "$status" -eq 1 ] || fail "no-plugins: want exit 1, got $status"
grep -q 'plugins' "$stderr_file" || fail "no-plugins: error should name the missing directory"

# --- so does one where CRS was never checked out
make_workspace no-crs no-crs
run_prepare apache "$compose" ''
[ "$status" -eq 1 ] || fail "no-crs: want exit 1, got $status"
grep -q 'crs/' "$stderr_file" || fail "no-crs: error should name the missing directory"

# --- extra config is appended to the mounted setup file, keeping what was there
make_workspace extra-conf
run_prepare apache "$compose" 'SecAction "id:900110,phase:1,pass,nolog"'
[ "$status" -eq 0 ] || fail "extra-conf: want exit 0, got $status"
grep -q '^# crs setup$' "$ws/crs/crs-setup.conf.example" || fail "extra-conf: overwrote the existing setup file"
grep -q 'id:900110' "$ws/crs/crs-setup.conf.example" || fail "extra-conf: directives were not appended"

# --- an empty extra config leaves the setup file byte for byte alone
make_workspace no-extra-conf
cp "$ws/crs/crs-setup.conf.example" "$ws/before"
run_prepare apache "$compose" ''
cmp -s "$ws/before" "$ws/crs/crs-setup.conf.example" || fail "no-extra-conf: setup file was modified"

# --- a missing compose source fails rather than starting an empty container
make_workspace no-compose
run_prepare apache "$ws/does-not-exist.yml" ''
[ "$status" -ne 0 ] || fail "no-compose: want a non-zero exit"

if [ "$failures" -eq 0 ]; then
  echo "all prepare.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
