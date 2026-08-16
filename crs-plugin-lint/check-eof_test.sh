#!/usr/bin/env bash
# Self-check for check-eof.sh.
#
# The cases below are the ones fernandrone/linelint's own end-of-file rule
# distinguishes at its defaults (`single-new-line: true`), so this doubles as
# the equivalence check for dropping that dependency.
#
# Run: ./crs-plugin-lint/check-eof_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
check="$here/check-eof.sh"
failures=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Writes $2 (printf format, so \n works) into a fresh tree and checks it.
# Sets: status, tree, output.
run_check() {
  local name=$1 content=$2
  tree="$workdir/$name"
  mkdir -p "$tree"
  # shellcheck disable=SC2059  # the content IS the format string, by design
  printf "$content" >"$tree/file.txt"
  output=$("$check" "$tree" 2>&1)
  status=$?
}

# --- the passing shapes
run_check single-newline 'a\n'
[ "$status" -eq 0 ] || fail "single-newline: want exit 0, got $status ($output)"

run_check just-a-newline '\n'
[ "$status" -eq 0 ] || fail "just-a-newline: want exit 0, got $status — upstream passes this too"

run_check multiline 'a\nb\nc\n'
[ "$status" -eq 0 ] || fail "multiline: want exit 0, got $status"

run_check blank-line-then-text '\n\na\n'
[ "$status" -eq 0 ] || fail "blank-line-then-text: only the END of the file matters"

# --- the failing shapes
run_check no-newline 'a'
[ "$status" -eq 1 ] || fail "no-newline: want exit 1, got $status"
grep -q 'No newline at end of file' <<<"$output" || fail "no-newline: wrong message"

run_check no-newline-longer 'ab'
[ "$status" -eq 1 ] || fail "no-newline-longer: want exit 1, got $status"

run_check two-newlines 'a\n\n'
[ "$status" -eq 1 ] || fail "two-newlines: want exit 1, got $status"
grep -q 'More than one newline' <<<"$output" || fail "two-newlines: wrong message"

run_check many-newlines 'a\n\n\n\n'
[ "$status" -eq 1 ] || fail "many-newlines: want exit 1, got $status"

# --- an empty file is valid, as it is upstream
tree="$workdir/empty"
mkdir -p "$tree"
: >"$tree/file.txt"
output=$("$check" "$tree" 2>&1)
status=$?
[ "$status" -eq 0 ] || fail "empty-file: want exit 0, got $status ($output)"

# --- annotations name the offending file, and every one of them
tree="$workdir/many"
mkdir -p "$tree/nested"
printf 'a' >"$tree/one.conf"
printf 'b\n\n' >"$tree/nested/two.conf"
printf 'ok\n' >"$tree/fine.conf"
output=$("$check" "$tree" 2>&1)
status=$?
[ "$status" -eq 1 ] || fail "many: want exit 1, got $status"
grep -q "::error file=$tree/one.conf::" <<<"$output" || fail "many: missing annotation for one.conf"
grep -q "::error file=$tree/nested/two.conf::" <<<"$output" || fail "many: nested file not checked"
grep -q 'fine.conf' <<<"$output" && fail "many: annotated a file that was fine"
grep -q '2 file(s)' <<<"$output" || fail "many: should report the total"

# --- binary files are skipped rather than reported
tree="$workdir/binary"
mkdir -p "$tree"
printf 'PNG\x00\x01\x02binary' >"$tree/image.png"
printf 'ok\n' >"$tree/fine.conf"
output=$("$check" "$tree" 2>&1)
status=$?
[ "$status" -eq 0 ] || fail "binary: a binary file without a trailing newline must not fail the check"

# --- .git is not walked
tree="$workdir/gitdir"
mkdir -p "$tree/.git"
printf 'no trailing newline' >"$tree/.git/HEAD"
printf 'ok\n' >"$tree/fine.conf"
output=$("$check" "$tree" 2>&1)
status=$?
[ "$status" -eq 0 ] || fail "gitdir: .git should be ignored"

# --- a missing directory is an error, not an empty pass
output=$("$check" "$workdir/does-not-exist" 2>&1)
status=$?
[ "$status" -eq 1 ] || fail "missing-dir: want exit 1"
grep -q 'is not a directory' <<<"$output" || fail "missing-dir: unhelpful error"

# --- filenames with spaces survive the walk, including leading ones
tree="$workdir/spaces"
mkdir -p "$tree/a dir"
printf 'x' >"$tree/a dir/a file.conf"
output=$("$check" "$tree" 2>&1)
status=$?
[ "$status" -eq 1 ] || fail "spaces: a file with spaces in its name must still be checked"
grep -q 'a file.conf' <<<"$output" || fail "spaces: filename mangled"

tree="$workdir/leading-space"
mkdir -p "$tree"
printf 'x' >"$tree/ leading.conf"
output=$("$check" "$tree" 2>&1)
status=$?
[ "$status" -eq 1 ] || fail "leading-space: a filename starting with a space must still be checked"
grep -q ' leading.conf' <<<"$output" || fail "leading-space: filename trimmed"

# a trailing space is what a bare `read` (without IFS=) would silently eat,
# skipping the file instead of reporting it
tree="$workdir/trailing-space"
mkdir -p "$tree"
printf 'x' >"$tree/trailing.conf "
output=$("$check" "$tree" 2>&1)
status=$?
[ "$status" -eq 1 ] || fail "trailing-space: a filename ending in a space must still be checked"

if [ "$failures" -eq 0 ]; then
  echo "all check-eof.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
