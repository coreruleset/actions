#!/usr/bin/env bash
# Prints the tag of the current CRS LTS release.
#
# Usage: resolve-lts.sh
#
# Needs `gh` on PATH with GH_TOKEN set. The LTS release is the most recent
# non-prerelease whose *name* is marked "(LTS)"; the tag itself carries no
# marker, so the name is the only thing to go on.

set -euo pipefail

tag=$(gh api --paginate repos/coreruleset/coreruleset/releases \
  --jq '[.[] | select(.prerelease == false) | select((.name // "") | test("\\(LTS\\)"))][0].tag_name')

if [ -z "$tag" ] || [ "$tag" = "null" ]; then
  echo "::error::Could not resolve the current CRS LTS release tag" >&2
  exit 1
fi

echo "$tag"
