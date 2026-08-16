#!/usr/bin/env bash
# Self-check for resolve-lts.sh, using a stubbed `gh`.
# Run: ./crs-plugin-test/resolve-lts_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
resolve="$here/resolve-lts.sh"
failures=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

stubs="$workdir/stubs"
mkdir -p "$stubs"

# `gh` answers `api ... --jq <filter>` by running the same filter with the real
# jq over the release list in $STUB_RELEASES, so the filter itself is tested.
cat >"$stubs/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
if [ -n "${STUB_GH_FAILS:-}" ]; then
  echo "stub gh: API request failed" >&2
  exit 1
fi
filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) filter=$2; shift 2 ;;
    *) shift ;;
  esac
done
jq -r "$filter" "$STUB_RELEASES"
STUB
chmod +x "$stubs/gh"

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Sets: status, stdout, STUB_STATE.
run_resolve() {
  local name=$1 releases=$2
  export STUB_STATE="$workdir/$name"
  mkdir -p "$STUB_STATE"
  export STUB_RELEASES="$STUB_STATE/releases.json"
  printf '%s' "$releases" >"$STUB_RELEASES"
  stdout=$(PATH="$stubs:$PATH" "$resolve" 2>"$STUB_STATE/stderr")
  status=$?
}

# --- picks the newest LTS release, skipping newer non-LTS ones
run_resolve picks-lts '[
  {"tag_name":"v4.22.0","name":"CRS v4.22.0","prerelease":false},
  {"tag_name":"v4.19.0","name":"CRS v4.19.0 (LTS)","prerelease":false},
  {"tag_name":"v4.10.0","name":"CRS v4.10.0 (LTS)","prerelease":false}
]'
[ "$status" -eq 0 ] || fail "picks-lts: want exit 0, got $status"
[ "$stdout" = "v4.19.0" ] || fail "picks-lts: want v4.19.0, got '$stdout'"

# --- ignores an LTS prerelease
run_resolve skips-prerelease '[
  {"tag_name":"v4.20.0-rc1","name":"CRS v4.20.0 (LTS)","prerelease":true},
  {"tag_name":"v4.19.0","name":"CRS v4.19.0 (LTS)","prerelease":false}
]'
[ "$stdout" = "v4.19.0" ] || fail "skips-prerelease: want v4.19.0, got '$stdout'"

# --- a release with no name at all does not blow up the filter
run_resolve null-name '[
  {"tag_name":"v4.21.0","name":null,"prerelease":false},
  {"tag_name":"v4.19.0","name":"CRS v4.19.0 (LTS)","prerelease":false}
]'
[ "$status" -eq 0 ] || fail "null-name: want exit 0, got $status"
[ "$stdout" = "v4.19.0" ] || fail "null-name: want v4.19.0, got '$stdout'"

# --- "(LTS)" is matched literally, not as a regex group
run_resolve literal-parens '[
  {"tag_name":"v4.21.0","name":"CRS v4.21.0 LTS","prerelease":false},
  {"tag_name":"v4.19.0","name":"CRS v4.19.0 (LTS)","prerelease":false}
]'
[ "$stdout" = "v4.19.0" ] || fail "literal-parens: want v4.19.0, got '$stdout'"

# --- no LTS release at all is an error, not an empty ref
run_resolve no-lts '[
  {"tag_name":"v4.22.0","name":"CRS v4.22.0","prerelease":false}
]'
[ "$status" -eq 1 ] || fail "no-lts: want exit 1, got $status"
[ -z "$stdout" ] || fail "no-lts: want no tag on stdout, got '$stdout'"
grep -q 'Could not resolve' "$STUB_STATE/stderr" || fail "no-lts: unhelpful error"

# --- a failing API call is an error too
run_resolve gh-fails '[]'
STUB_GH_FAILS=1 run_resolve gh-fails '[]'
[ "$status" -ne 0 ] || fail "gh-fails: want a non-zero exit"

if [ "$failures" -eq 0 ]; then
  echo "all resolve-lts.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
