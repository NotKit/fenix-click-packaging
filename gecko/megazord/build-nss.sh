#!/bin/bash
# Build a static NSS+NSPR for aarch64 Linux, in the layout application-services
# expects in $NSS_DIR -- i.e. what its own libs/build-nss-desktop.sh produces,
# for a target that script cannot build.
#
#   APPSERVICES=<checkout> ./build-nss.sh [--out DIR] [--jobs N]
#
# Why static: appservices' ohttp fork hard-codes static linking for the app-svc
# feature (ohttp/build.rs setup_for_app_svc: use_static_softoken=true,
# use_static_nspr=true), so a dynamic NSS_DIR links `nss_build_common` fine and
# then fails in ohttp.  Static is what the published megazord is built with.
#
# The NSS version, archive and sha256 are appservices' own (libs/build-all.sh),
# and so is the symbol-rename patch: NSS's HMAC_Update and friends clash with
# OpenSSL's, and the published megazord carries the renamed symbols.
#
# Cross-compiling is NSS's own supported path: --target=arm64 with CC/CCC set to
# the cross compiler and --build-tools-cc for the host tools NSPR's configure
# builds and runs (nsinstall).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${APPSERVICES:?set APPSERVICES to an application-services checkout}"
AS="$APPSERVICES"
OUT="${NSS_OUT:-$ROOT/build/megazord/nss-arm64-static}"
WORK="${NSS_WORK:-$ROOT/build/megazord/nss-build}"
GYP="${GYP:-}"
CROSS="${CROSS:-aarch64-linux-gnu}"
CC_CROSS="${CC_CROSS:-$CROSS-gcc-14}"
CXX_CROSS="${CXX_CROSS:-$CROSS-g++-14}"
JOBS="${JOBS:-$(nproc)}"

while [ $# -gt 0 ]; do
	case "$1" in
	--out)  OUT="$2"; shift ;;
	--jobs) JOBS="$2"; shift ;;
	*) echo "usage: see the header of $0" >&2; exit 2 ;;
	esac
	shift
done

NSS=nss-3.125
ARCHIVE=nss-3.125-with-nspr-4.39.tar.gz
URL="https://ftp.mozilla.org/pub/security/nss/releases/NSS_3_125_RTM/src/$ARCHIVE"
SHA=fa3e7dcd151a7f3331a2dbf4cc57bcf4444e4c9c2b67ac00363409a7c4ecfa9d

command -v "$CC_CROSS" >/dev/null || { echo "no $CC_CROSS" >&2; exit 1; }
# NSS's build needs gyp; it is not packaged on every distribution, so make one.
if [ -z "$GYP" ]; then
	GYP="$WORK/gypenv/bin"
	if [ ! -x "$GYP/gyp" ]; then
		mkdir -p "$WORK"
		python3 -m venv "$WORK/gypenv"
		"$WORK/gypenv/bin/pip" install -q gyp-next
	fi
fi
[ -x "$GYP/gyp" ] || { echo "no gyp in $GYP" >&2; exit 1; }

mkdir -p "$WORK"; cd "$WORK"
if [ ! -e "$ARCHIVE" ]; then
	if [ -e "$AS/libs/$ARCHIVE" ]; then cp "$AS/libs/$ARCHIVE" .; else curl -sfSL --retry 3 -O "$URL"; fi
fi
echo "$SHA  $ARCHIVE" | sha256sum -c -

rm -rf "$NSS"
tar xzf "$ARCHIVE"
SRC="$WORK/$NSS"

# appservices' symbol-rename patch, applied the same way build-all.sh does
python3 - "$SRC/nss/coreconf/config.gypi" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if 'NSS_HMAC_Update' in s:
    sys.exit(0)
anchor = """      '<(nss_dist_dir)/private/<(module)',
    ],
"""
defines = """      '<(nss_dist_dir)/private/<(module)',
    ],
    'defines': [
      'HMAC_Update=NSS_HMAC_Update',
      'HMAC_Init=NSS_HMAC_Init',
      'CMAC_Update=NSS_CMAC_Update',
      'CMAC_Init=NSS_CMAC_Init',
      'MD5_Update=NSS_MD5_Update',
      'SHA1_Update=NSS_SHA1_Update',
      'SHA256_Update=NSS_SHA256_Update',
      'SHA224_Update=NSS_SHA224_Update',
      'SHA512_Update=NSS_SHA512_Update',
      'SHA384_Update=NSS_SHA384_Update',
      'SEED_set_key=NSS_SEED_set_key',
      'SEED_encrypt=NSS_SEED_encrypt',
      'SEED_decrypt=NSS_SEED_decrypt',
      'SEED_ecb_encrypt=NSS_SEED_ecb_encrypt',
      'SEED_cbc_encrypt=NSS_SEED_cbc_encrypt',
    ],
"""
assert anchor in s, "config.gypi anchor moved; re-check against libs/build-all.sh"
open(p, 'w').write(s.replace(anchor, defines, 1))
print("config.gypi: symbol renames applied")
PY

# NSPR's configure gets --host="${CC%-*}", i.e. CC with its last dash-component
# stripped, so CC has to be exactly the triple plus "-gcc": with Ubuntu's
# versioned aarch64-linux-gnu-gcc-14 that yields --host=aarch64-linux-gnu-gcc
# and config.sub rejects it ("OS `gcc' not recognized").
mkdir -p "$WORK/bin"
ln -sf "$(command -v "$CC_CROSS")" "$WORK/bin/$CROSS-gcc"
ln -sf "$(command -v "$CXX_CROSS")" "$WORK/bin/$CROSS-g++"

export PATH="$GYP:$WORK/bin:$PATH"
export CC="$CROSS-gcc" CCC="$CROSS-g++" CXX="$CROSS-g++"
export AR="$CROSS-ar" RANLIB="$CROSS-ranlib" NM="$CROSS-nm"

cd "$SRC/nss"
./build.sh -v --opt --static --disable-tests --python=python3 \
	--target=arm64 --build-tools-cc=gcc -j "$JOBS" \
	-Ddisable_dbm=1 -Dsign_libs=0 -Ddisable_libpkix=1

DIST="$SRC/dist"; OBJ="$DIST/Release"
rm -rf "$OUT"; mkdir -p "$OUT/lib" "$OUT/include/nss"
# the same file list as libs/build-nss-desktop.sh, with its aarch64 branch
for l in libplc4.a libplds4.a libnspr4.a \
	libcertdb.a libcerthi.a libcryptohi.a libfreebl_static.a libgcm.a \
	libnss_static.a libmozpkix.a libnssb.a libnssdev.a libnsspki.a libnssutil.a \
	libpk11wrap_static.a libpkcs12.a libpkcs7.a libsmime.a libsoftokn_static.a libssl.a \
	libarmv8_c_lib.a libghash-aes-aarch64_c_lib.a; do
	cp -p -L "$OBJ/lib/$l" "$OUT/lib/"
done
cp -p -L -R "$DIST/public/nss/"* "$OUT/include/nss/"
cp -p -L -R "$OBJ/include/nspr/"* "$OUT/include/nss/"

echo "== $OUT"
ls "$OUT/lib" | wc -l
file -b "$OUT/lib/libnss_static.a" | head -1
"$CROSS-nm" --defined-only "$OUT/lib/libnss_static.a" 2>/dev/null | grep -c ' T ' || true
