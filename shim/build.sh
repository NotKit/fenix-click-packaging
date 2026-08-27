#!/bin/bash
# Build the libcore/dalvik/android.system/android.icu compat shim:
#
#   $OUT/shim.jar        the classes ART's boot class path has and a JDK lacks
#   $OUT/libportshim.so  the JNI back end android.system.Os needs
#
# The jar is architecture-independent, so a host javac makes it whatever the
# target is; the .so is not, so $CC is the cross compiler and $JNI_JAVA_HOME the
# *target* JDK (jni.h only -- nothing here links libjvm).
#
# Usage: shim/build.sh <outdir>
#
# Vendored from firefox-atl jvm-run/shim; SOURCE.md says what was left behind.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:?usage: build.sh <outdir>}"
mkdir -p "$OUT"
WORK="$OUT/shim-build"
SHIM_JAR="$OUT/shim.jar"
SHIM_LIB="$OUT/libportshim.so"

: "${JAVA_HOME:?set JAVA_HOME to the host JDK 21}"
: "${JNI_JAVA_HOME:=$JAVA_HOME}"
export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | grep -q 'version "21\.' ||
	{ echo "shim: need a JDK 21 (JAVA_HOME=$JAVA_HOME)" >&2; exit 1; }

CLASSES="$WORK/classes"
rm -rf "$CLASSES"; mkdir -p "$CLASSES"

# --- the jar ----------------------------------------------------------------
mapfile -t sources < <(find "$HERE/src" -name '*.java' | sort)
echo "shim: compiling ${#sources[@]} sources"
# --release 21 with no -classpath: the shim must not grow a dependency on the
# framework, or the split between framework and runtime library stops being real.
javac --release 21 -Xlint:-options -implicit:none -Werror -d "$CLASSES" "${sources[@]}"
# resources/ holds the service registrations that make a shim the platform
# default the way libcore's are on ART.
jar --create --date=2020-01-01T00:00:00Z --file "$SHIM_JAR" \
	-C "$CLASSES" . -C "$HERE/resources" .

# Nothing outside the packages ART owns and the JDK lacks -- above all nothing
# in java.*/javax.*, where the boot loader wins and a sealed package can split.
ALLOWED='^(libcore/|dalvik/|android/system/|android/icu/|org/xmlpull/|org/kxml2/|org/json/|org/apache/harmony/|META-INF/)'
strays="$(unzip -Z1 "$SHIM_JAR" | grep -vE "$ALLOWED" | grep -v '/$' || true)"
[ -z "$strays" ] || {
	echo "shim.jar holds entries outside the packages the shim may define:" >&2
	printf '%s\n' "$strays" >&2
	exit 1
}

# --- the JNI back end -------------------------------------------------------
echo "shim: building libportshim.so with ${CC:-cc}"
"${CC:-cc}" -shared -fPIC -O2 -Wall -Wextra -std=gnu11 \
	-I"$JNI_JAVA_HOME/include" -I"$JNI_JAVA_HOME/include/linux" \
	-o "$SHIM_LIB" "$HERE/native/port_shim.c"
# A missing export here is not a load failure: NativeAllocationRegistry falls
# back to leaking the native peer and only says so in the log.
symbols="$("${NM:-nm}" -D --defined-only "$SHIM_LIB")"
for symbol in Java_libcore_util_NativeAllocationRegistry_applyFreeFunction \
	Java_libcore_io_Posix_open Java_libcore_io_Posix_setsockoptInt \
	Java_libcore_io_Posix_sysconf Java_libcore_io_Memory_peekByte \
	Java_libcore_io_Memory_peekIntNative Java_libcore_io_Memory_pokeByteArrayNative; do
	grep -q "$symbol" <<<"$symbols" ||
		{ echo "libportshim.so does not export $symbol" >&2; exit 1; }
done

echo "shim: $SHIM_JAR ($(du -h "$SHIM_JAR" | cut -f1)), $SHIM_LIB"
