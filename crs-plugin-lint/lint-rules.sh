#!/usr/bin/env bash
# Runs secrules-parser over a plugin's rule files.
#
# Usage: lint-rules.sh <plugin_dir>
#
# Needs `secrules-parser` on PATH.

set -euo pipefail

plugin_dir=${1:?plugin_dir is required}

# An unmatched glob would reach secrules-parser as the literal string
# "plugins/*.conf", which it reports as a missing file rather than as an empty
# plugin, so the files are collected here instead.
conf_files=()
while IFS= read -r conf; do
  conf_files+=("$conf")
done < <(find "$plugin_dir" -maxdepth 1 -name '*.conf' | sort)

if [ ${#conf_files[@]} -eq 0 ]; then
  echo "::error::No .conf files in \"$plugin_dir\"; a plugin needs at least one rule file" >&2
  exit 1
fi

echo "Linting ${#conf_files[@]} rule file(s) in $plugin_dir" >&2
secrules-parser -c -v --output-type github -f "${conf_files[@]}"
