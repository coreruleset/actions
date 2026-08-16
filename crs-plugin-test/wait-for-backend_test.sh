#!/usr/bin/env bash
# Self-check for wait-for-backend.sh, using stubbed `docker`, `curl` and `sleep`.
# Run: ./crs-plugin-test/wait-for-backend_test.sh

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
wait_for="$here/wait-for-backend.sh"
failures=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

stubs="$workdir/stubs"
mkdir -p "$stubs"

# `docker inspect` reports Running until $STUB_STOPS_AFTER polls have gone by;
# `docker compose ... logs` records that it was asked for the logs.
cat >"$stubs/docker" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
if [ "${1:-}" = "compose" ]; then
  echo "logs" >>"$STUB_STATE/compose_calls"
  echo "stub compose logs"
  exit 0
fi
polls=$(cat "$STUB_STATE/inspect_calls" 2>/dev/null || echo 0)
polls=$((polls + 1))
echo "$polls" >"$STUB_STATE/inspect_calls"
if [ -n "${STUB_STOPS_AFTER:-}" ] && [ "$polls" -gt "$STUB_STOPS_AFTER" ]; then
  echo "false"
else
  echo "true"
fi
STUB

# `curl` fails until $STUB_READY_AFTER attempts have been made.
cat >"$stubs/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
tries=$(cat "$STUB_STATE/curl_calls" 2>/dev/null || echo 0)
tries=$((tries + 1))
echo "$tries" >"$STUB_STATE/curl_calls"
[ "$tries" -ge "${STUB_READY_AFTER:-1}" ]
STUB

cat >"$stubs/sleep" <<'STUB'
#!/usr/bin/env bash
echo "$@" >>"$STUB_STATE/sleeps"
STUB

chmod +x "$stubs/docker" "$stubs/curl" "$stubs/sleep"

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Runs wait-for-backend.sh in a fresh sandbox. Sets: status, STUB_STATE.
run_wait() {
  local name=$1
  shift
  export STUB_STATE="$workdir/$name"
  mkdir -p "$STUB_STATE"
  PATH="$stubs:$PATH" "$wait_for" "$@" >"$STUB_STATE/stdout" 2>"$STUB_STATE/stderr"
  status=$?
}

count() { cat "$STUB_STATE/$1" 2>/dev/null || echo 0; }

sleeps() {
  if [ -f "$STUB_STATE/sleeps" ]; then
    wc -l <"$STUB_STATE/sleeps" | tr -d ' '
  else
    echo 0
  fi
}

# --- returns as soon as the backend answers, without burning the timeout
STUB_READY_AFTER=1 run_wait ready apache compose.yml 60
[ "$status" -eq 0 ] || fail "ready: want exit 0, got $status"
[ "$(count curl_calls)" = 1 ] || fail "ready: want 1 curl attempt, got $(count curl_calls)"
[ "$(sleeps)" = 0 ] || fail "ready: should not have slept, slept $(sleeps) times"
[ ! -s "$STUB_STATE/compose_calls" ] || fail "ready: should not dump logs on success"

# --- keeps polling while the server is still coming up
STUB_READY_AFTER=4 run_wait slow apache compose.yml 60
[ "$status" -eq 0 ] || fail "slow: want exit 0, got $status"
[ "$(count curl_calls)" = 4 ] || fail "slow: want 4 curl attempts, got $(count curl_calls)"
[ "$(sleeps)" = 3 ] || fail "slow: want 3 sleeps between attempts, got $(sleeps)"

# --- gives up at the timeout, and says where it was looking
STUB_READY_AFTER=999 run_wait timeout apache compose.yml 5
[ "$status" -eq 1 ] || fail "timeout: want exit 1, got $status"
[ "$(count curl_calls)" = 5 ] || fail "timeout: want 5 attempts in a 5s budget, got $(count curl_calls)"
grep -q 'did not answer' "$STUB_STATE/stderr" || fail "timeout: unhelpful error"
grep -q 'http://localhost' "$STUB_STATE/stderr" || fail "timeout: error should name the url"
[ -s "$STUB_STATE/compose_calls" ] || fail "timeout: should dump compose logs on failure"

# --- a container that dies is reported as such, not as a timeout
STUB_READY_AFTER=999 STUB_STOPS_AFTER=2 run_wait crashed apache compose.yml 60
[ "$status" -eq 1 ] || fail "crashed: want exit 1, got $status"
grep -q 'stopped before it became ready' "$STUB_STATE/stderr" || fail "crashed: should not look like a timeout"
[ "$(count curl_calls)" -lt 5 ] || fail "crashed: should bail out early, made $(count curl_calls) attempts"
[ -s "$STUB_STATE/compose_calls" ] || fail "crashed: should dump compose logs"

# --- the timeout defaults, and the url is overridable for nginx on another port
STUB_READY_AFTER=999 run_wait default-timeout apache compose.yml
[ "$(count curl_calls)" = 60 ] || fail "default-timeout: want a 60s default, got $(count curl_calls)"

STUB_READY_AFTER=999 WAIT_FOR_BACKEND_URL=http://localhost:8080 run_wait custom-url apache compose.yml 2
grep -q 'localhost:8080' "$STUB_STATE/stderr" || fail "custom-url: url override ignored"

# --- missing arguments are a usage error
if PATH="$stubs:$PATH" "$wait_for" >/dev/null 2>&1; then
  fail "no-args: want a non-zero exit"
fi

if [ "$failures" -eq 0 ]; then
  echo "all wait-for-backend.sh checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
