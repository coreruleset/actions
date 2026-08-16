#!/usr/bin/env bash
# Checks that the release-please config and manifest agree with the actions on disk.
#
# Usage: check-release-config.sh [repo_root]
#
# Two failure modes are silent without this check, and both mean an action can
# be merged but never released correctly:
#
#   - a package with a missing or empty "component" tags as "v1.2.0" instead of
#     "check-label-v1.2.0", because release-please defaults component to ""
#   - a new action directory that nobody added to the config is never released
#     at all, and nothing fails to tell you

set -euo pipefail

root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
config="$root/.github/release-please-config.json"
manifest="$root/.github/.release-please-manifest.json"

errors=0

problem() {
  echo "::error::$1" >&2
  errors=$((errors + 1))
}

for file in "$config" "$manifest"; do
  if [ ! -f "$file" ]; then
    echo "::error::Missing $file" >&2
    exit 1
  fi
  if ! jq empty "$file" 2>/dev/null; then
    echo "::error::$file is not valid JSON" >&2
    exit 1
  fi
done

# tags must be "<component>-v<version>", never a bare "v<version>"
for flag in include-component-in-tag include-v-in-tag; do
  if [ "$(jq -r --arg f "$flag" '.[$f]' "$config")" != "true" ]; then
    problem "\"$flag\" must be true, or releases will not be tagged \"<action>-v<version>\""
  fi
done

packages=$(jq -r '.packages | keys[]' "$config")

while IFS= read -r package; do
  [ -n "$package" ] || continue

  component=$(jq -r --arg p "$package" '.packages[$p].component // ""' "$config")
  if [ -z "$component" ]; then
    problem "Package \"$package\" has no \"component\"; its tag would be \"v<version>\""
  elif [ "$component" != "$package" ]; then
    problem "Package \"$package\" declares component \"$component\"; they must match"
  fi

  if ! jq -e --arg p "$package" '.packages[$p].paths | index($p)' "$config" >/dev/null; then
    problem "Package \"$package\" does not list \"$package\" in its \"paths\""
  fi

  if [ ! -f "$root/$package/action.yml" ]; then
    problem "Package \"$package\" has no $package/action.yml"
  fi

  if ! jq -e --arg p "$package" 'has($p)' "$manifest" >/dev/null; then
    problem "Package \"$package\" is missing from the manifest"
  else
    # versions are seeded by hand when an action inherits a version from another
    # repository, and release-please reads them literally: a leading "v" or a
    # stray space is not rejected, it just produces a nonsense next version
    version=$(jq -r --arg p "$package" '.[$p]' "$manifest")
    if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' <<<"$version"; then
      problem "Manifest version for \"$package\" is \"$version\"; expected a bare semver such as 3.0.2, with no leading \"v\""
    fi
  fi
done <<<"$packages"

# every action on disk must be released by something
while IFS= read -r action_yml; do
  [ -n "$action_yml" ] || continue
  action=$(basename "$(dirname "$action_yml")")
  if ! grep -qx "$action" <<<"$packages"; then
    problem "Action \"$action\" is not in $config and can never be released"
  fi
done < <(find "$root" -mindepth 2 -maxdepth 2 -name action.yml -not -path '*/.*' | sort)

while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  if ! grep -qx "$entry" <<<"$packages"; then
    problem "Manifest entry \"$entry\" has no package in $config"
  fi
done < <(jq -r 'keys[]' "$manifest")

if [ "$errors" -gt 0 ]; then
  echo "::error::$errors problem(s) in the release-please configuration" >&2
  exit 1
fi

echo "release-please config matches the actions on disk" >&2
