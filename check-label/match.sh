#!/usr/bin/env bash
# Reads PR label names on stdin, one per line. Exits 0 if at least one of them
# satisfies the required list, 1 otherwise.
#
# Usage: match.sh <prefix_mode> <one_of>
#   prefix_mode  "true" to match a label that starts with a required string,
#                anything else for exact equality
#   one_of       comma separated list of required strings

set -euo pipefail

prefix_mode=${1:?prefix_mode is required}
one_of=${2:?one_of is required}

IFS=',' read -ra checks <<<"$one_of"

while IFS= read -r label || [ -n "$label" ]; do
  [ -n "$label" ] || continue
  for check in "${checks[@]}"; do
    check=$(printf '%s' "$check" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$check" ] || continue
    if [ "$prefix_mode" = "true" ]; then
      case "$label" in
        "$check"*)
          echo "Label \"$label\" matches required prefix \"$check\""
          exit 0
          ;;
      esac
    elif [ "$label" = "$check" ]; then
      echo "Label \"$label\" matches required label \"$check\""
      exit 0
    fi
  done
done

echo "::error::Pull request needs one of these labels: $one_of" >&2
exit 1
