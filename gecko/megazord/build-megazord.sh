#!/bin/bash
# Cross-build application-services' full megazord for aarch64 Linux -- the one
# native the JVM vehicle needs and Mozilla does not publish for this target
# (they ship linux-x86-64 and darwin).
#
#   APPSERVICES=<checkout> ./build-nss.sh && APPSERVICES=<checkout> ./build-megazord.sh
#     -> build/megazord/libmegazord.so   (stripped, ~22.5 MB)
#
# MEGAZORD_REV is the last commit on appservices `main` before the nightly the
# class path pins, and MEGAZORD_VERSION is that nightly's version string: the
# built library reports the version its Kotlin bindings expect.
#
# Verification is not "it linked": with MEGAZORD_REF pointing at Mozilla's
# published x86_64 build, the uniffi symbol sets are diffed.  Equal sets mean
# every Kotlin `Native.register` on the class path binds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${APPSERVICES:?set APPSERVICES to an application-services checkout}"
AS="$APPSERVICES"
REV="${MEGAZORD_REV:-3f6bd4d96e43e61a712578c16b148a82316e6b0a}"
VER="${MEGAZORD_VERSION:-155.20260807050256}"
NSS="${NSS_DIR:-$ROOT/build/megazord/nss-arm64-static}"
# An aarch64 libz.so: the one system library the link needs that the cross
# toolchain does not ship.  Gecko's own bootstrap sysroot has one.
SYSLIBS="${SYSLIBS:-$HOME/.mozbuild/sysroot-aarch64-linux-gnu/usr/lib/aarch64-linux-gnu}"
OUT="${MEGAZORD_OUT:-$ROOT/build/megazord/libmegazord.so}"
REF="${MEGAZORD_REF:-}"
CROSS=aarch64-linux-gnu
CC_CROSS="${CC_CROSS:-$CROSS-gcc-14}"

[ -d "$NSS/lib" ] || { echo "no $NSS -- run build-nss.sh first" >&2; exit 1; }
[ -e "$SYSLIBS/libz.so" ] || { echo "no aarch64 libz in $SYSLIBS" >&2; exit 1; }

cd "$AS"
git checkout -q "$REV"

export PATH="$HOME/.cargo/bin:$PATH"
export NSS_DIR="$NSS"
# ohttp's app-svc path links NSS statically regardless, so the whole build does
export NSS_STATIC=1
export MEGAZORD_VERSION="$VER"
export CC_aarch64_unknown_linux_gnu="$CC_CROSS"
export CXX_aarch64_unknown_linux_gnu="$CROSS-g++-14"
export AR_aarch64_unknown_linux_gnu="$CROSS-ar"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="$CC_CROSS"
# zlib is the one system library the link needs that the cross toolchain does
# not ship; everything else comes from NSS_DIR or the crates themselves.
export RUSTFLAGS="-L $SYSLIBS ${RUSTFLAGS:-}"

cargo build -p megazord --release --target aarch64-unknown-linux-gnu

BUILT="$AS/target/aarch64-unknown-linux-gnu/release/libmegazord.so"
mkdir -p "$(dirname "$OUT")"
"$CROSS-strip" -o "$OUT" "$BUILT"
ls -l "$OUT"
"$CROSS-readelf" -d "$OUT" | grep NEEDED

if [ -n "$REF" ] && [ -e "$REF" ]; then
	a=$(mktemp); b=$(mktemp)
	nm -D --defined-only "$REF" | awk '{print $3}' | grep '^uniffi_' | sort -u > "$a"
	"$CROSS-nm" -D --defined-only "$OUT" | awk '{print $3}' | grep '^uniffi_' | sort -u > "$b"
	echo "uniffi symbols: published x86_64 $(wc -l < "$a"), this build $(wc -l < "$b")"
	if diff -q "$a" "$b" >/dev/null; then
		echo "uniffi surface identical to the published megazord"
	else
		echo "DIFFERENT uniffi surface -- wrong revision?" >&2
		diff "$a" "$b" | head -20 >&2
		rm -f "$a" "$b"; exit 1
	fi
	rm -f "$a" "$b"
else
	echo "no reference megazord (MEGAZORD_REF) -- symbol check skipped" >&2
fi
