#!/usr/bin/env bash
# Self-check for lint-rules.sh, using a stubbed `secrules-parser`.
# Run: ./crs-plugin-lint/lint-rules_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
lint="$here/lint-rules.sh"
failures=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

stubs="$workdir/stubs"
mkdir -p "$stubs"

cat >"$stubs/secrules-parser" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$@" >>"$STUB_STATE/args"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$stubs/secrules-parser"

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Sets: status, plugins, STUB_STATE.
run_lint() {
  local name=$1
  shift
  export STUB_STATE="$workdir/$name"
  mkdir -p "$STUB_STATE"
  plugins="$STUB_STATE/plugins"
  mkdir -p "$plugins"
  for conf in "$@"; do
    : >"$plugins/$conf"
  done
  PATH="$stubs:$PATH" "$lint" "$plugins" >"$STUB_STATE/stdout" 2>"$STUB_STATE/stderr"
  status=$?
}

# --- passes every rule file to the parser
run_lint two-files example-config.conf example-rules.conf
[ "$status" -eq 0 ] || fail "two-files: want exit 0, got $status"
grep -q 'example-config.conf' "$STUB_STATE/args" || fail "two-files: config file not linted"
grep -q 'example-rules.conf' "$STUB_STATE/args" || fail "two-files: rules file not linted"

# --- an empty plugins directory is an error, not a silent pass
run_lint empty
[ "$status" -eq 1 ] || fail "empty: want exit 1, got $status"
grep -q 'needs at least one rule file' "$STUB_STATE/stderr" || fail "empty: unhelpful error"
[ ! -f "$STUB_STATE/args" ] || fail "empty: should not have run the parser"

# --- an unmatched glob is never passed through as a literal
run_lint no-conf README.md
[ "$status" -eq 1 ] || fail "no-conf: want exit 1, got $status"
[ ! -f "$STUB_STATE/args" ] || fail "no-conf: should not have run the parser"

# --- a parser failure fails the step
STUB_EXIT=1 run_lint parser-fails example-rules.conf
[ "$status" -ne 0 ] || fail "parser-fails: a failing parser must fail the step"

# --- only the plugin directory itself is linted, not nested fixtures
run_lint nested example-rules.conf
mkdir -p "$plugins/nested" && : >"$plugins/nested/other.conf"
PATH="$stubs:$PATH" "$lint" "$plugins" >/dev/null 2>&1
grep -q 'nested/other.conf' "$STUB_STATE/args" && fail "nested: should not descend into subdirectories"

# --- a missing directory is a usage error
if PATH="$stubs:$PATH" "$lint" >/dev/null 2>&1; then
  fail "no-args: want a non-zero exit"
fi

if [ "$failures" -eq 0 ]; then
  echo "all lint-rules.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
