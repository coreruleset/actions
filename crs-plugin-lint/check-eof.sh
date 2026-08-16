#!/usr/bin/env bash
# Checks that every text file ends in exactly one newline.
#
# Usage: check-eof.sh [directory]
#
# Replaces fernandrone/linelint's end-of-file rule at its defaults, which is all
# the CRS plugin repositories ever used it for (none of them ship a
# .linelint.yml). Reports one GitHub annotation per offending file.
#
# The rule, matching linelint's `single-new-line: true`:
#   - an empty file passes
#   - the last byte must be a newline
#   - the byte before it must not be, so "a\n\n" fails and "a\n" passes
#   - a file that is exactly "\n" passes, as it does upstream

set -euo pipefail

directory=${1:-.}

if [ ! -d "$directory" ]; then
  echo "::error::\"$directory\" is not a directory" >&2
  exit 1
fi

failed=0

while IFS= read -r file; do
  # skip binary files, as linelint's IsText does; this also skips empty files,
  # which the rule considers valid anyway
  LC_ALL=C grep -qI '' "$file" 2>/dev/null || continue

  if [ "$(tail -c 1 "$file" | wc -l | tr -d ' ')" -eq 0 ]; then
    echo "::error file=${file}::No newline at end of file"
    failed=$((failed + 1))
  elif [ "$(tail -c 2 "$file" | wc -l | tr -d ' ')" -ge 2 ]; then
    echo "::error file=${file}::More than one newline at end of file"
    failed=$((failed + 1))
  fi
done < <(find "$directory" -type f -not -path '*/.git/*' | sort)

if [ "$failed" -gt 0 ]; then
  echo "::error::$failed file(s) do not end in exactly one newline" >&2
  exit 1
fi

echo "every text file ends in exactly one newline" >&2
