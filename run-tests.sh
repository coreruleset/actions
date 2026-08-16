#!/usr/bin/env bash
# Runs every action's self-checks.
# Run: ./run-tests.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
failed=()

for test in "$here"/*_test.sh "$here"/*/*_test.sh; do
  echo "==> ${test#"$here/"}"
  "$test" || failed+=("${test#"$here/"}")
done

if [ ${#failed[@]} -gt 0 ]; then
  echo
  echo "failed: ${failed[*]}"
  exit 1
fi

echo
echo "all action self-checks passed"
