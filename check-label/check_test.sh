#!/usr/bin/env bash
# Self-check for check.sh, using a stubbed `gh`.
# Run: ./check-label/check_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
check="$here/check.sh"
failures=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

stubs="$workdir/stubs"
mkdir -p "$stubs"

# `gh` records its arguments and prints the labels in $STUB_LABELS, one per
# line. When $STUB_GH_FAILS is set it still prints them and then fails, the way
# a connection dropped mid-response would.
cat >"$stubs/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$@" >>"$STUB_STATE/gh_args"
printf '%s' "${STUB_LABELS:-}"
if [ -n "${STUB_GH_FAILS:-}" ]; then
  echo "stub gh: could not resolve pull request" >&2
  exit 1
fi
STUB
chmod +x "$stubs/gh"

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Runs check.sh in a fresh sandbox. Sets: status, STUB_STATE.
run_check() {
  local name=$1
  shift
  export STUB_STATE="$workdir/$name"
  mkdir -p "$STUB_STATE"
  PATH="$stubs:$PATH" "$check" "$@" >"$STUB_STATE/stdout" 2>"$STUB_STATE/stderr"
  status=$?
}

# --- passes when the pull request carries a required label
STUB_LABELS=$'docs\nbug' run_check match 42 coreruleset/actions false 'bug,enhancement'
[ "$status" -eq 0 ] || fail "match: want exit 0, got $status"

# --- fails when it does not
STUB_LABELS=$'docs' run_check no-match 42 coreruleset/actions false 'bug,enhancement'
[ "$status" -eq 1 ] || fail "no-match: want exit 1, got $status"
grep -q 'needs one of these labels' "$STUB_STATE/stderr" || fail "no-match: no explanation on stderr"

# --- fails when the pull request has no labels at all
STUB_LABELS='' run_check no-labels 42 coreruleset/actions false 'bug'
[ "$status" -eq 1 ] || fail "no-labels: want exit 1, got $status"

# --- asks gh for the right pull request, in the right repository
STUB_LABELS='bug' run_check gh-args 42 coreruleset/actions false 'bug'
grep -qx '42' "$STUB_STATE/gh_args" || fail "gh-args: pull request number not passed to gh"
grep -qx 'coreruleset/actions' "$STUB_STATE/gh_args" || fail "gh-args: repository not passed to gh"

# --- prefix mode reaches match.sh
STUB_LABELS='release/minor' run_check prefix 42 coreruleset/actions true 'release/'
[ "$status" -eq 0 ] || fail "prefix: want exit 0, got $status"
STUB_LABELS='release/minor' run_check no-prefix 42 coreruleset/actions false 'release/'
[ "$status" -eq 1 ] || fail "no-prefix: exact mode should not match a prefix"

# --- a failing gh fails the check even if it printed a matching label first
STUB_LABELS='bug' STUB_GH_FAILS=1 run_check gh-fails 42 coreruleset/actions false 'bug'
[ "$status" -ne 0 ] || fail "gh-fails: a failed gh call must not pass the check"

# --- run outside a pull request event
run_check no-pr '' coreruleset/actions false 'bug'
[ "$status" -eq 1 ] || fail "no-pr: want exit 1, got $status"
grep -q 'only runs on pull_request' "$STUB_STATE/stderr" || fail "no-pr: unhelpful error"
[ ! -s "$STUB_STATE/gh_args" ] || fail "no-pr: should not have called gh"

if [ "$failures" -eq 0 ]; then
  echo "all check.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
