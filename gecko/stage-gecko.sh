#!/bin/bash
# Stage a built Gecko objdir as the payload's gecko/ directory.
#
#   ./stage-gecko.sh --objdir DIR [--out DIR] [--abi arm64-v8a]
#
# Three steps, in this order:
#
#   1. omni.ja, written into the objdir's own dist/bin/assets/.  The build never
#      reaches stage-package, and the unpacked fallback in Omnijar::InitOne
#      cannot work in an android-toolkit build: OMNIJAR_NAME is "assets/omni.ja"
#      and nsLocalFile::AppendNative rejects any fragment containing '/', so
#      Omnijar::FallibleInit fails and NS_InitXPCOM returns
#      NS_ERROR_OMNIJAR_CORRUPT.  fenix/stage-apk.sh puts this file in the APK.
#   2. dist/bin, with the debug sections taken out.  libxul.so is 3.1 GB
#      unstripped and 2.8 GB of that is .debug*.
#   3. liblog.so and libatlndkstub.so from the link shim.  libxul's DT_NEEDED
#      names both and neither is on the device.
#
# Then every shared object is checked: right architecture, dynamic section
# intact, no debug sections left.  That check is the point of the script -- a
# stripped-wrong or host-architecture .so fails on the phone at dlopen time,
# hours after this ran.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

OBJDIR=""
OUT="$ROOT/build/gecko"
ABI="arm64-v8a"
MACHINE="AArch64"
SHIM="$HERE/android-libs-shim-arm64"
: "${OBJCOPY:=$HOME/.mozbuild/clang/bin/llvm-objcopy}"
: "${READELF:=$HOME/.mozbuild/clang/bin/llvm-readelf}"
# A later pref() call wins, so this appends and does not replace.
: "${SWWR:=1}"

while [ $# -gt 0 ]; do
	case "$1" in
	--objdir) OBJDIR="$2"; shift ;;
	--out)    OUT="$2"; shift ;;
	--shim)   SHIM="$2"; shift ;;
	--abi)    ABI="$2"; shift ;;
	--machine) MACHINE="$2"; shift ;;
	*) echo "usage: see the header of $0" >&2; exit 2 ;;
	esac
	shift
done

[ -n "$OBJDIR" ] || { echo "missing --objdir" >&2; exit 2; }
DIST="$OBJDIR/dist/bin"
[ -f "$DIST/libxul.so" ] || { echo "no $DIST/libxul.so" >&2; exit 1; }
command -v "$OBJCOPY" >/dev/null || { echo "no objcopy at $OBJCOPY" >&2; exit 1; }
command -v "$READELF" >/dev/null || { echo "no readelf at $READELF" >&2; exit 1; }
for f in liblog.so libatlndkstub.so; do
	[ -f "$SHIM/$f" ] ||
		{ echo "no $SHIM/$f -- run android-libs-shim/regenerate.sh" >&2; exit 1; }
done

echo "== 1/3 omni.ja (MOZ_ANDROID_CPU_ABI=$ABI)"
install -m644 "$HERE/atl-defaults.js" "$DIST/defaults/pref/atl-defaults.js"
if [ "$SWWR" = 0 ]; then
	echo 'pref("gfx.webrender.software", false);' >> "$DIST/defaults/pref/atl-defaults.js"
fi
(
	cd "$DIST"
	mkdir -p assets
	rm -f assets/omni.ja
	zip -q -X -r -0 assets/omni.ja \
		actors chrome chrome.manifest components contentaccessible defaults \
		hyphenation localization modules moz-src res "$ABI"

	# greprefs.js a second time, at the top level.  InitInitialObjects reads
	# "$MOZ_ANDROID_CPU_ABI/greprefs.js" and falls back to a top-level
	# "greprefs.js", and an android-toolkit build installs the file only under
	# the ABI directory.  The ABI string is not ours to pick: GeckoLoader
	# putenvs MOZ_ANDROID_CPU_ABI=Build.CPU_ABI, and the translation layer
	# fills ro.product.cpu.abi in only when os.arch is x86_64, so on the phone
	# Gecko asks for "unknown/greprefs.js".  A missing greprefs.js fails the
	# whole of Preferences::GetInstanceForService, which leaves sPImpl null and
	# SIGSEGVs later in Preferences::InitializeUserPrefs.
	tmp="$(mktemp -d)"
	cp "$ABI/greprefs.js" "$tmp/greprefs.js"
	( cd "$tmp" && zip -q -X -0 "$DIST/assets/omni.ja" greprefs.js )
	rm -rf "$tmp"
	echo "   omni.ja: $(stat -c%s assets/omni.ja) bytes"
)

echo "== 2/3 dist/bin, debug sections removed"
# --strip-debug and not --strip-all: .symtab is 1% of the tree and it is the
# difference between a device backtrace with names and one with addresses.
rm -rf "$OUT"; mkdir -p "$OUT"
list="$(mktemp)"
( cd "$DIST" && find . -mindepth 1 \( -path ./assets -prune \) -o -print0 ) > "$list"
n=0; stripped=0
while IFS= read -r -d '' f; do
	src="$DIST/${f#./}"; dst="$OUT/${f#./}"
	if [ -L "$src" ]; then cp -P "$src" "$dst"; continue; fi
	if [ -d "$src" ]; then mkdir -p "$dst"; continue; fi
	if [ "$(od -An -N4 -c "$src" 2>/dev/null | tr -d ' \n')" = "177ELF" ]; then
		"$OBJCOPY" --strip-debug "$src" "$dst"
		chmod --reference="$src" "$dst"
		stripped=$((stripped+1))
	else
		cp -p "$src" "$dst"
	fi
	n=$((n+1))
done < "$list"
rm -f "$list"
echo "   $n files, $stripped ELF stripped"

echo "== 3/3 link shim"
install -m755 "$SHIM/libatlndkstub.so" "$OUT/libatlndkstub.so"
install -m755 "$SHIM/liblog.so" "$OUT/liblog.so"

echo "== verify"
bad=0
for f in $(cd "$OUT" && find . -name '*.so' -o -name '*.so.*' | sed 's|^\./||'); do
	m="$("$READELF" -h "$OUT/$f" 2>/dev/null | awk '/Machine:/{$1="";print}')"
	case "$m" in *"$MACHINE"*) ;;
		*) echo "   NOT $MACHINE: $f ($m)"; bad=1; continue ;; esac
	dbg="$("$READELF" -S "$OUT/$f" | grep -c '\.debug_' || true)"
	[ "$dbg" = 0 ] || { echo "   still has debug sections: $f"; bad=1; }
done
[ "$bad" = 0 ] || { echo "verification failed" >&2; exit 1; }
echo "staged $OUT ($(du -sh "$OUT" | cut -f1))"
