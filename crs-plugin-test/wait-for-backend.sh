#!/usr/bin/env bash
# Waits for a started backend container to be running and answering requests.
#
# Usage: wait-for-backend.sh <container> <compose_file> [timeout_seconds]
#
# Replaces the fixed `sleep 5` the CRS workflows have carried: it returns as
# soon as the container answers, and on failure dumps the compose logs so the
# job shows why rather than just that ftw could not connect.

set -euo pipefail

container=${1:?container is required}
compose_file=${2:?compose_file is required}
timeout=${3:-60}

url=${WAIT_FOR_BACKEND_URL:-http://localhost}

give_up() {
  echo "::error::$1" >&2
  docker compose -f "$compose_file" logs >&2 || true
  exit 1
}

echo "Waiting up to ${timeout}s for $container" >&2

elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
  if [ "$(docker inspect "$container" --format='{{.State.Running}}' 2>/dev/null)" != "true" ]; then
    give_up "$container stopped before it became ready"
  fi
  # any HTTP response means the server is up; CRS may answer 403 by design
  if curl --silent --output /dev/null --max-time 5 "$url"; then
    echo "$container is ready after ${elapsed}s" >&2
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

give_up "$container did not answer on $url within ${timeout}s"
