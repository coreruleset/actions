#!/usr/bin/env bash
# Self-check for install.sh, using stubbed `gh`, `uname` and `sleep`.
# Run: ./install-go-ftw/install_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
install="$here/install.sh"
failures=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

stubs="$workdir/stubs"
mkdir -p "$stubs"

# `gh` records its arguments, fails the first $STUB_GH_FAILURES calls, and then
# writes a tarball containing an `ftw` file where the real one would.
cat >"$stubs/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$@" >>"$STUB_STATE/gh_args"
count=$(cat "$STUB_STATE/gh_calls" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" >"$STUB_STATE/gh_calls"
archive=""
dir="."
while [ $# -gt 0 ]; do
  case "$1" in
    -p) archive=$2; shift 2 ;;
    -D) dir=$2; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$dir"
if [ "$count" -le "${STUB_GH_FAILURES:-0}" ]; then
  # a reset connection leaves a truncated file behind
  printf 'partial' >"$dir/$archive"
  echo "stub gh: simulated failure $count" >&2
  exit 1
fi
payload="$STUB_STATE/payload"
mkdir -p "$payload"
printf '#!/bin/sh\necho stub-ftw\n' >"$payload/ftw"
chmod +x "$payload/ftw"
tar -czf "$dir/$archive" -C "$payload" ftw
STUB

cat >"$stubs/uname" <<'STUB'
#!/usr/bin/env bash
echo "${STUB_ARCH:-x86_64}"
STUB

cat >"$stubs/sleep" <<'STUB'
#!/usr/bin/env bash
echo "$@" >>"$STUB_STATE/sleeps"
STUB

chmod +x "$stubs/gh" "$stubs/uname" "$stubs/sleep"

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Runs install.sh in a fresh sandbox. Sets: status, stdout, dest, STUB_STATE.
run_install() {
  local name=$1 arch=$2 gh_failures=$3
  shift 3
  export STUB_STATE="$workdir/$name"
  export STUB_ARCH="$arch"
  export STUB_GH_FAILURES="$gh_failures"
  mkdir -p "$STUB_STATE"
  dest="$workdir/$name/dest"
  stdout=$(PATH="$stubs:$PATH" "$install" "$@" 2>"$STUB_STATE/stderr")
  status=$?
}

gh_calls() { cat "$STUB_STATE/gh_calls" 2>/dev/null || echo 0; }

sleep_count() {
  if [ -f "$STUB_STATE/sleeps" ]; then
    wc -l <"$STUB_STATE/sleeps" | tr -d ' '
  else
    echo 0
  fi
}

# --- downloads and extracts on the first attempt
run_install first-try x86_64 0 2.5.0 "$workdir/first-try/dest"
[ "$status" -eq 0 ] || fail "first-try: want exit 0, got $status"
[ -x "$dest/ftw" ] || fail "first-try: ftw was not extracted"
[ "$stdout" = "$dest/ftw" ] || fail "first-try: want '$dest/ftw' on stdout, got '$stdout'"
[ "$(gh_calls)" = 1 ] || fail "first-try: want 1 gh call, got $(gh_calls)"
[ -z "$(find "$dest" -name '*.tar.gz')" ] || fail "first-try: archive was left behind"

# --- a leading v in the version is optional, and the asset name drops it
run_install bare-version x86_64 0 2.5.0 "$workdir/bare-version/dest"
grep -qx 'ftw_2.5.0_linux_amd64.tar.gz' "$STUB_STATE/gh_args" || fail "bare-version: wrong asset requested"
grep -qx 'v2.5.0' "$STUB_STATE/gh_args" || fail "bare-version: wrong release tag requested"

run_install v-version x86_64 0 v2.5.0 "$workdir/v-version/dest"
grep -qx 'ftw_2.5.0_linux_amd64.tar.gz' "$STUB_STATE/gh_args" || fail "v-version: wrong asset requested"
grep -qx 'v2.5.0' "$STUB_STATE/gh_args" || fail "v-version: wrong release tag requested"

# --- retries a reset connection, then succeeds
run_install retry x86_64 2 2.5.0 "$workdir/retry/dest"
[ "$status" -eq 0 ] || fail "retry: want exit 0, got $status"
[ -x "$dest/ftw" ] || fail "retry: ftw was not extracted after retries"
[ "$(gh_calls)" = 3 ] || fail "retry: want 3 gh calls, got $(gh_calls)"
[ "$(sleep_count)" = 2 ] || fail "retry: want 2 backoff sleeps, got $(sleep_count)"
grep -q '^5$' "$STUB_STATE/sleeps" || fail "retry: want a 5 second first backoff"
grep -q '^10$' "$STUB_STATE/sleeps" || fail "retry: want a 10 second second backoff"

# --- gives up after three attempts, leaving nothing behind
run_install give-up x86_64 3 2.5.0 "$workdir/give-up/dest"
[ "$status" -eq 1 ] || fail "give-up: want exit 1, got $status"
[ "$(gh_calls)" = 3 ] || fail "give-up: want 3 gh calls, got $(gh_calls)"
grep -q 'Giving up' "$STUB_STATE/stderr" || fail "give-up: no explanation on stderr"
[ -z "$(find "$dest" -name '*.tar.gz' 2>/dev/null)" ] || fail "give-up: archive was left behind"

# --- picks the asset for the runner's architecture
run_install arm x86_64 0 2.5.0 "$workdir/arm/dest" # sanity: amd64 covered above
run_install aarch64 aarch64 0 2.5.0 "$workdir/aarch64/dest"
grep -qx 'ftw_2.5.0_linux_arm64.tar.gz' "$STUB_STATE/gh_args" || fail "aarch64: want the arm64 asset"
run_install arm64 arm64 0 2.5.0 "$workdir/arm64/dest"
grep -qx 'ftw_2.5.0_linux_arm64.tar.gz' "$STUB_STATE/gh_args" || fail "arm64: want the arm64 asset"

# --- fails on an architecture go-ftw does not publish, without downloading
run_install riscv riscv64 0 2.5.0 "$workdir/riscv/dest"
[ "$status" -eq 1 ] || fail "riscv: want exit 1, got $status"
[ "$(gh_calls)" = 0 ] || fail "riscv: should not have called gh"
grep -q 'riscv64' "$STUB_STATE/stderr" || fail "riscv: error should name the architecture"

# --- creates the destination directory, and defaults it to the working directory
run_install nested x86_64 0 2.5.0 "$workdir/nested/dest/deep/deeper"
[ -x "$workdir/nested/dest/deep/deeper/ftw" ] || fail "nested: destination was not created"

export STUB_STATE="$workdir/default-dest"
mkdir -p "$STUB_STATE/cwd"
stdout=$(cd "$STUB_STATE/cwd" && PATH="$stubs:$PATH" STUB_ARCH=x86_64 STUB_GH_FAILURES=0 "$install" 2.5.0)
[ "$stdout" = "./ftw" ] || fail "default-dest: want './ftw' on stdout, got '$stdout'"
[ -x "$STUB_STATE/cwd/ftw" ] || fail "default-dest: ftw not extracted into the working directory"

# --- a missing version is a usage error
if PATH="$stubs:$PATH" "$install" >/dev/null 2>&1; then
  fail "no-version: want a non-zero exit"
fi

if [ "$failures" -eq 0 ]; then
  echo "all install.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
