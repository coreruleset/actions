#!/usr/bin/env bash
# Lays out the workspace that the plugin test compose file expects.
#
# Usage: prepare.sh <backend> <compose_source> [extra_conf]
#   backend         apache or nginx
#   compose_source  docker-compose.yml to copy into tests/integration/
#   extra_conf      directives to append to crs/crs-setup.conf.example
#
# Runs in the caller's workspace.

set -euo pipefail

backend=${1:?backend is required}
compose_source=${2:?compose_source is required}
extra_conf=${3-}

case "$backend" in
  apache | nginx) ;;
  *)
    echo "::error::Unknown backend \"$backend\", expected apache or nginx" >&2
    exit 1
    ;;
esac

# The compose file bind mounts these. Docker would silently create empty
# directories in their place, and the tests would fail much later with an
# unhelpful "no rules matched" instead of pointing at the missing input.
for required in plugins crs/rules crs/crs-setup.conf.example; do
  if [ ! -e "$required" ]; then
    echo "::error::Expected \"$required\" in the workspace; run this action from a CRS plugin repository" >&2
    exit 1
  fi
done

mkdir -p tests/integration "tests/logs/$backend"
# the container writes its logs here as a different user
chmod a+rw "tests/logs/$backend"

cp "$compose_source" tests/integration/docker-compose.yml

# crs-setup.conf.example is mounted into the container as the CRS setup file
if [ -n "$extra_conf" ]; then
  printf '\n%s\n' "$extra_conf" >>crs/crs-setup.conf.example
fi
