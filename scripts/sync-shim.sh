#!/bin/bash
# Refresh shim/{src,native,resources} from the firefox-atl working tree, where
# the shim is developed.
#
#   scripts/sync-shim.sh /path/to/firefox-atl
#
# build.sh here is deliberately not overwritten; shim/SOURCE.md says why.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: sync-shim.sh FIREFOX_ATL_DIR}/jvm-run/shim"
[ -d "$SRC/src" ] || { echo "no shim sources at $SRC" >&2; exit 1; }
for d in src native resources; do
	rsync -a --delete "$SRC/$d/" "$HERE/shim/$d/"
done
echo "shim synced from $SRC"
git -C "$HERE" status --short shim/ || true
