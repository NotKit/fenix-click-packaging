#!/bin/bash
# Link libmozglue.so out of a built objdir.
#
#   ./build-mozglue.sh --objdir DIR [--out FILE] [--shim DIR] [--rpath DIR]
#
# A route-B objdir has MOZ_FOLD_LIBS empty and never reaches stage-package, so
# it produces no libmozglue.so of its own; the objects are there and the library
# is relinked here from xpcshell.list.  Two things this link does that a plain
# copy of the objdir's objects would not:
#
#  * links the shim's liblog.so.  APKOpen.o has a strong undefined
#    __android_log_print; without a DT_NEEDED for it, System.loadLibrary
#    ("mozglue") fails outright.
#  * links mozglue-selfglobal.o, which promotes the library into the loader's
#    global scope so libxul's weak-undefined allocator symbols bind.  Without
#    it, dlopening libxul segfaults in protobuf's global constructor at
#    operator new -> address 0.  See mozglue-selfglobal.c.
#
# The payload keeps this library in gecko/ beside libxul.so: GeckoLoader
# putenvs MOZ_ANDROID_LIBDIR from wherever it found libmozglue, and APKOpen
# then dlopens libnss3, libnspr4, libplc4 and libmozsqlite3 out of that same
# directory -- which is where they already are.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

OBJDIR=""
OUT="$ROOT/build/mozglue/libmozglue.so"
SHIM="$HERE/android-libs-shim-arm64"
# DT_RUNPATH for liblog.so, as the loader will see it -- a device path, so it
# does not resolve here and does on the phone.  The click's own layout puts
# every native in one directory, so $ORIGIN is what that install wants.
RPATH='$ORIGIN'
# SELFGLOBAL=0 links without the promotion, which is how to reproduce the
# segfault it exists to prevent.
: "${SELFGLOBAL:=1}"

while [ $# -gt 0 ]; do
	case "$1" in
	--objdir) OBJDIR="$2"; shift ;;
	--out)    OUT="$2"; shift ;;
	--shim)   SHIM="$2"; shift ;;
	--rpath)  RPATH="$2"; shift ;;
	*) echo "usage: see the header of $0" >&2; exit 2 ;;
	esac
	shift
done

[ -n "$OBJDIR" ] || { echo "missing --objdir" >&2; exit 2; }
LIST="$OBJDIR/js/xpconnect/shell/xpcshell.list"
[ -f "$LIST" ] || { echo "no $LIST" >&2; exit 1; }
[ -f "$SHIM/liblog.so" ] ||
	{ echo "no $SHIM/liblog.so -- run android-libs-shim/regenerate.sh" >&2; exit 1; }

# The compiler and link flags the objdir was configured with, so a cross build
# is linked by its own cross toolchain with no second copy of the knowledge.
read -r -d '' PY <<'EOF' || true
import json, shlex, sys
s = json.load(open(sys.argv[1]))['substs']
print(shlex.join(list(s['CXX']) + s.get('DSO_LDOPTS', []) + s.get('OS_LDFLAGS', [])))
EOF
FLAGS="$(python3 -c "$PY" "$OBJDIR/config.status.json")"
# These objects genuinely have undefined symbols the executable's other halves
# supply, so -z defs (from OS_LDFLAGS) has to go.
FLAGS="${FLAGS/-Wl,-z,defs/}"
# The C compiler for the one object built here: same driver, C mode.
CC="${CC:-$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['substs']['CC'][0])" "$OBJDIR/config.status.json")}"
CC_ARGS="$(python3 -c "import json,shlex,sys;print(shlex.join(json.load(open(sys.argv[1]))['substs']['CC'][1:]))" "$OBJDIR/config.status.json")"

OBJS=()
while read -r o; do
	[ -z "$o" ] && continue
	[ "$o" = "xpcshell.o" ] && continue   # has main()
	OBJS+=("$(cd "$(dirname "$LIST")" && readlink -f "$o")")
done < "$LIST"
# third_party/fmt has FINAL_LIBRARY = "mozglue" but is not on xpcshell.list, so
# libxul's weak-undefined fmt::v11::detail::vformat_to and friends would resolve
# to 0 and every MOZ_LOG line would SIGSEGV inside LogModuleManager::PrintFmt.
# Same shape as the allocator symbols.
FMT_OBJ="$OBJDIR/third_party/fmt/Unified_cpp_third_party_fmt0.o"
[ -f "$FMT_OBJ" ] && OBJS+=("$FMT_OBJ")
echo "${#OBJS[@]} mozglue objects from $LIST"

mkdir -p "$(dirname "$OUT")"
SELF_OBJ=()
if [ "$SELFGLOBAL" != 0 ]; then
	# shellcheck disable=SC2086
	$CC $CC_ARGS -O1 -g -fPIC -c -o "$(dirname "$OUT")/mozglue-selfglobal.o" \
		"$HERE/mozglue-selfglobal.c"
	SELF_OBJ=("$(dirname "$OUT")/mozglue-selfglobal.o")
fi

SHIM_ABS="$(cd "$SHIM" && pwd)"
# shellcheck disable=SC2086
$FLAGS -o "$OUT" "${OBJS[@]}" ${SELF_OBJ[0]+"${SELF_OBJ[@]}"} \
	-L"$SHIM_ABS" -llog -Wl,-rpath,"$RPATH" \
	-ldl -lrt
rm -f "$(dirname "$OUT")/mozglue-selfglobal.o"
echo "linked $OUT ($(stat -c%s "$OUT") bytes)"
