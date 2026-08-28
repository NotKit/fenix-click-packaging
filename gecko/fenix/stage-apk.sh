#!/bin/bash
# Turn the Gradle-built Fenix APK into the resource container the payload uses.
#
#   ./stage-apk.sh --apk-dir DIR --omni FILE [--abi arm64-v8a] [--out FILE]
#
# The translation layer's AssetManager finds resource containers by scanning the
# class path for zips holding an AndroidManifest.xml, and PackageParser reads
# that manifest as AAPT binary XML, so an APK is mandatory even though nothing
# in it is executed: its dex and its lib/ are inert on a JVM class path.
#
# The APK build-classpath.sh produces has no omni.ja and no Gecko .so of its own
# -- geckoview's assets and jniLibs srcDirs point at $topobjdir/dist/geckoview,
# which this objdir does not produce -- so the objdir's omni.ja is simply added.
# Stored, not deflated: the omnijar reader mmaps it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

APK_DIR=""
OMNI=""
ABI="arm64-v8a"
OUT="$ROOT/build/fenix/fenix-jvm.apk"

while [ $# -gt 0 ]; do
	case "$1" in
	--apk-dir) APK_DIR="$2"; shift ;;
	--omni)    OMNI="$2"; shift ;;
	--abi)     ABI="$2"; shift ;;
	--out)     OUT="$2"; shift ;;
	*) echo "usage: see the header of $0" >&2; exit 2 ;;
	esac
	shift
done

[ -n "$APK_DIR" ] || { echo "missing --apk-dir" >&2; exit 2; }
[ -n "$OMNI" ] || { echo "missing --omni" >&2; exit 2; }
[ -f "$OMNI" ] || { echo "no $OMNI -- run stage-gecko.sh first" >&2; exit 1; }

# Absolute: the last zip below runs inside a temporary directory, and a
# relative --out would be created there and lost.
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
OMNI="$(cd "$(dirname "$OMNI")" && pwd)/$(basename "$OMNI")"

IN=$(find "$APK_DIR" -maxdepth 1 \( -name "*-${ABI}-*.apk" -o -name "*-${ABI}.apk" \) | head -1)
[ -n "$IN" ] || { echo "no $ABI apk in $APK_DIR" >&2; exit 1; }

rm -f "$OUT"
cp "$IN" "$OUT"
zip -q -d "$OUT" assets/omni.ja >/dev/null 2>&1 || true

STAGE="$(mktemp -d)"
mkdir -p "$STAGE/assets"
cp "$OMNI" "$STAGE/assets/omni.ja"
( cd "$STAGE" && zip -q -X -0 "$OUT" assets/omni.ja )
rm -rf "$STAGE"

listing=$(unzip -l "$OUT")
for entry in AndroidManifest.xml resources.arsc assets/omni.ja; do
	grep -q "$entry" <<<"$listing" || { echo "$OUT has no $entry" >&2; exit 1; }
done
echo "$OUT  $(stat -c %s "$OUT") bytes  (from $(basename "$IN"))"
