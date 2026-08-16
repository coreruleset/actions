#!/usr/bin/env bash
# Self-check for match.sh. Run: ./check-label/match_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
match="$here/match.sh"
failures=0

assert() {
  local want=$1 prefix_mode=$2 one_of=$3 labels=$4
  local got
  printf '%s' "$labels" | "$match" "$prefix_mode" "$one_of" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL: prefix_mode=$prefix_mode one_of='$one_of' labels='$labels' want=$want got=$got"
    failures=$((failures + 1))
  fi
}

# exact mode
assert 0 false 'bug,enhancement' $'docs\nbug'
assert 1 false 'bug,enhancement' $'docs\nchore'
assert 0 false 'bug, enhancement' $'enhancement'      # whitespace after comma is trimmed
assert 0 false 'good first issue' $'good first issue' # labels may contain spaces
assert 1 false 'bug' ''                               # no labels at all
assert 1 false 'bug' $'bugfix'                        # exact mode is not a prefix match

# prefix mode
assert 0 true 'release/' $'release/minor'
assert 1 true 'release/' $'minor/release'
assert 1 true 'release/' $'release'                   # shorter than the prefix

if [ "$failures" -eq 0 ]; then
  echo "all match.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
