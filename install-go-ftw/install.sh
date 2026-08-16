#!/usr/bin/env bash
# Downloads a go-ftw release and extracts the `ftw` binary.
#
# Usage: install.sh <version> [destination]
#   version      go-ftw release, with or without the leading "v" (e.g. 2.5.0)
#   destination  directory to extract `ftw` into, default the current directory
#
# Needs `gh` on PATH with GH_TOKEN set. Progress goes to stderr; the path to the
# extracted binary is the only thing written to stdout.

set -euo pipefail

version=${1:?version is required}
destination=${2:-.}
version=${version#v}

# ftw runs on the runner, so its architecture decides the asset. Asking the
# runner keeps this from drifting apart from any runs-on mapping, and an
# architecture with no release fails here rather than on the first exec.
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *)
    echo "::error::No go-ftw release for runner architecture $(uname -m)" >&2
    exit 1
    ;;
esac

archive="ftw_${version}_linux_${arch}.tar.gz"
mkdir -p "$destination"

# The release CDN resets connections now and then. Download to a file so a
# truncated transfer fails here instead of reaching tar, and retry it.
for attempt in 1 2 3; do
  if gh release download -R coreruleset/go-ftw "v${version}" \
    -p "$archive" -D "$destination" --clobber >&2; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    rm -f "${destination:?}/${archive}"
    echo "::error::Giving up on ${archive} after ${attempt} attempts" >&2
    exit 1
  fi
  delay=$((attempt * 5))
  echo "Download failed, retrying in ${delay} seconds" >&2
  sleep "$delay"
done

tar -xzf "${destination}/${archive}" -C "$destination" ftw
rm "${destination}/${archive}"

echo "${destination}/ftw"
