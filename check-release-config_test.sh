#!/usr/bin/env bash
# Self-check for check-release-config.sh.
# Run: ./check-release-config_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
check="$here/check-release-config.sh"
failures=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Builds a fake repository. $2 is the config, $3 the manifest, and any further
# arguments are action directories to create. Sets: root, status, output.
make_repo() {
  local name=$1 config=$2 manifest=$3
  shift 3
  root="$workdir/$name"
  mkdir -p "$root/.github"
  printf '%s' "$config" >"$root/.github/release-please-config.json"
  printf '%s' "$manifest" >"$root/.github/.release-please-manifest.json"
  for action in "$@"; do
    mkdir -p "$root/$action"
    : >"$root/$action/action.yml"
  done
}

run_check() {
  output=$("$check" "$root" 2>&1)
  status=$?
}

GOOD_CONFIG='{
  "include-component-in-tag": true,
  "include-v-in-tag": true,
  "packages": {
    "alpha": {"component": "alpha", "paths": ["alpha"]},
    "beta": {"component": "beta", "paths": ["beta", ".github/workflows/beta.yaml"]}
  }
}'
GOOD_MANIFEST='{"alpha": "0.0.0", "beta": "1.2.3"}'

# --- a consistent repository passes, extra paths and all
make_repo good "$GOOD_CONFIG" "$GOOD_MANIFEST" alpha beta
run_check
[ "$status" -eq 0 ] || fail "good: want exit 0, got $status ($output)"

# --- the real repository passes
output=$("$check" "$here" 2>&1)
status=$?
[ "$status" -eq 0 ] || fail "real-repo: this repository's own config must be valid ($output)"

# --- an action on disk that nobody registered can never be released
make_repo unregistered "$GOOD_CONFIG" "$GOOD_MANIFEST" alpha beta gamma
run_check
[ "$status" -eq 1 ] || fail "unregistered: want exit 1, got $status"
grep -q 'can never be released' <<<"$output" || fail "unregistered: unhelpful error"
grep -q 'gamma' <<<"$output" || fail "unregistered: error should name the action"

# --- an empty component silently produces a bare "v1.2.0" tag
make_repo empty-component '{
  "include-component-in-tag": true,
  "include-v-in-tag": true,
  "packages": {"alpha": {"component": "", "paths": ["alpha"]}}
}' '{"alpha": "0.0.0"}' alpha
run_check
[ "$status" -eq 1 ] || fail "empty-component: want exit 1, got $status"
grep -q 'no "component"' <<<"$output" || fail "empty-component: unhelpful error"

# --- so does a missing one
make_repo no-component '{
  "include-component-in-tag": true,
  "include-v-in-tag": true,
  "packages": {"alpha": {"paths": ["alpha"]}}
}' '{"alpha": "0.0.0"}' alpha
run_check
[ "$status" -eq 1 ] || fail "no-component: want exit 1, got $status"

# --- a component that does not match its package key
make_repo mismatched '{
  "include-component-in-tag": true,
  "include-v-in-tag": true,
  "packages": {"alpha": {"component": "alfa", "paths": ["alpha"]}}
}' '{"alpha": "0.0.0"}' alpha
run_check
[ "$status" -eq 1 ] || fail "mismatched: want exit 1, got $status"
grep -q 'they must match' <<<"$output" || fail "mismatched: unhelpful error"

# --- the tag-shape flags are required
for flag in include-component-in-tag include-v-in-tag; do
  make_repo "flag-$flag" "$(jq --arg f "$flag" 'del(.[$f])' <<<"$GOOD_CONFIG")" "$GOOD_MANIFEST" alpha beta
  run_check
  [ "$status" -eq 1 ] || fail "flag-$flag: dropping \"$flag\" must fail"
  grep -q "$flag" <<<"$output" || fail "flag-$flag: error should name the flag"
done

# --- a package whose paths omit its own directory would never match a commit
make_repo bad-paths '{
  "include-component-in-tag": true,
  "include-v-in-tag": true,
  "packages": {"alpha": {"component": "alpha", "paths": ["somewhere-else"]}}
}' '{"alpha": "0.0.0"}' alpha
run_check
[ "$status" -eq 1 ] || fail "bad-paths: want exit 1, got $status"

# --- config and manifest must list the same components
make_repo missing-in-manifest "$GOOD_CONFIG" '{"alpha": "0.0.0"}' alpha beta
run_check
[ "$status" -eq 1 ] || fail "missing-in-manifest: want exit 1, got $status"
grep -q 'missing from the manifest' <<<"$output" || fail "missing-in-manifest: unhelpful error"

make_repo extra-in-manifest "$GOOD_CONFIG" '{"alpha": "0.0.0", "beta": "1.2.3", "ghost": "9.9.9"}' alpha beta
run_check
[ "$status" -eq 1 ] || fail "extra-in-manifest: want exit 1, got $status"
grep -q 'ghost' <<<"$output" || fail "extra-in-manifest: error should name the entry"

# --- manifest versions must be bare semver, since they are seeded by hand
make_repo v-prefix "$GOOD_CONFIG" '{"alpha": "v1.0.0", "beta": "1.2.3"}' alpha beta
run_check
[ "$status" -eq 1 ] || fail "v-prefix: a leading \"v\" in the manifest must fail"
grep -q 'no leading' <<<"$output" || fail "v-prefix: unhelpful error"

make_repo not-semver "$GOOD_CONFIG" '{"alpha": "1.0", "beta": "1.2.3"}' alpha beta
run_check
[ "$status" -eq 1 ] || fail "not-semver: want exit 1, got $status"

make_repo prerelease "$GOOD_CONFIG" '{"alpha": "1.0.0-rc1", "beta": "1.2.3"}' alpha beta
run_check
[ "$status" -eq 0 ] || fail "prerelease: a prerelease version is valid ($output)"

# --- a package with no action.yml on disk
make_repo missing-action "$GOOD_CONFIG" "$GOOD_MANIFEST" alpha
run_check
[ "$status" -eq 1 ] || fail "missing-action: want exit 1, got $status"
grep -q 'action.yml' <<<"$output" || fail "missing-action: unhelpful error"

# --- every problem is reported, not just the first
make_repo many '{
  "include-component-in-tag": false,
  "include-v-in-tag": true,
  "packages": {"alpha": {"component": "", "paths": ["alpha"]}}
}' '{"alpha": "0.0.0"}' alpha gamma
run_check
grep -q '3 problem(s)' <<<"$output" || fail "many: want all 3 problems reported, got: $output"

# --- malformed or missing files fail loudly
make_repo broken-json 'not json at all' '{"alpha": "0.0.0"}' alpha
run_check
[ "$status" -eq 1 ] || fail "broken-json: want exit 1, got $status"
grep -q 'not valid JSON' <<<"$output" || fail "broken-json: unhelpful error"

root="$workdir/no-config"
mkdir -p "$root"
run_check
[ "$status" -eq 1 ] || fail "no-config: want exit 1, got $status"
grep -q 'Missing' <<<"$output" || fail "no-config: unhelpful error"

if [ "$failures" -eq 0 ]; then
  echo "all check-release-config.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
