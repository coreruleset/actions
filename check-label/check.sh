#!/usr/bin/env bash
# Fails unless the pull request carries one of the required labels.
#
# Usage: check.sh <pr_number> <repo> <prefix_mode> <one_of>
#
# Needs `gh` on PATH with GH_TOKEN set.

set -euo pipefail

pr_number=${1-}
repo=${2:?repo is required}
prefix_mode=${3:?prefix_mode is required}
one_of=${4:?one_of is required}

if [ -z "$pr_number" ]; then
  echo "::error::check-label only runs on pull_request events" >&2
  exit 1
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

gh pr view "$pr_number" --repo "$repo" --json labels --jq '.labels[].name' \
  | "$here/match.sh" "$prefix_mode" "$one_of"
