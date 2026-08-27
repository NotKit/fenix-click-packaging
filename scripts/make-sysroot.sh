#!/bin/bash
# Assemble the arm64 build-time sysroot this package cannot cross-build, and
# pack it as fenix-jvm-sysroot-arm64.tar.zst for a GitHub release.
#
#   scripts/make-sysroot.sh --from-art-click DIR --skia-src DIR [--out FILE]
#   scripts/make-sysroot.sh --from-stage DIR --skia DIR [--out FILE]
#
# What is in it, and why none of it is built by build.sh:
#
#   usr/lib/art/*.so        libtranslation_layer_main.so's DT_NEEDED --
#                           libandroidfw (AssetManager2, ResTable) and liblog,
#                           plus their own. art_standalone has no cross build:
#                           it is self-hosted only, which is exactly what makes
#                           the ART click packaging a multi-hour qemu build and
#                           this one a minutes-long cross build.
#   usr/lib/java/*.jar      ART's boot jars. javac compiles atlas's framework
#                           against libcore, not against the JDK.
#   usr/lib/libglfw.so*     atlas's window/input backend; noble ships GLFW 3.3
#                           and atlas needs 3.4's libdecor init hint.
#   usr/include/{androidfw,GLFW}   headers for the above.
#   skia/                   libskia.so plus skia's include/ and modules/. skia's
#                           gn build is not driven from atlas's meson and does
#                           not cross-compile from it; atlas's own
#                           -Dskia-prebuilt option exists for this.
#
# --from-art-click DIR points at an arm64 build tree of the *ART* click
# packaging (its build/aarch64-linux-gnu/app directory), which builds all of the
# above natively; its atlas-build/subprojects/skia holds the built libskia.so
# but not skia's headers, so --skia-src names the skia checkout they come from
# (they are architecture-independent). --skia DIR is the one-directory form,
# for a tree that already has libskia.so, include/ and modules/ together.
#
# Everything here is a build input, never shipped: the click carries the .so
# files it actually links and none of the headers or jars.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE=""; SKIA_SRC=""; SKIA_LIB=""; OUT="$HERE/dist/fenix-jvm-sysroot-arm64.tar.zst"

while [ $# -gt 0 ]; do
	case "$1" in
	--from-art-click) STAGE="$2/stage/usr"
	                  SKIA_LIB="$2/atlas-build/subprojects/skia/libskia.so"; shift ;;
	--from-stage)     STAGE="$2"; shift ;;
	--skia)           SKIA_SRC="$2"; SKIA_LIB="$2/libskia.so"; shift ;;
	--skia-src)       SKIA_SRC="$2"; shift ;;
	--skia-lib)       SKIA_LIB="$2"; shift ;;
	--out)            OUT="$2"; shift ;;
	*) echo "usage: see the header of $0" >&2; exit 2 ;;
	esac
	shift
done
[ -n "$STAGE" ] || { echo "need a staged sysroot (--from-art-click or --from-stage)" >&2; exit 2; }
[ -n "$SKIA_SRC" ] && [ -n "$SKIA_LIB" ] ||
	{ echo "need skia headers and a built libskia.so (--skia, or --skia-src + --skia-lib)" >&2; exit 2; }

for f in "$STAGE/lib/art/libandroidfw.so" "$STAGE/lib/java/core-all_classes.jar" \
         "$STAGE/lib/libglfw.so.3" "$STAGE/include/androidfw" \
         "$SKIA_SRC/include/core/SkCanvas.h" "$SKIA_LIB"; do
	[ -e "$f" ] || { echo "missing input: $f" >&2; exit 1; }
done
case "$(file -bL "$SKIA_LIB")" in *"ARM aarch64"*) ;;
	*) echo "$SKIA_LIB is not aarch64" >&2; exit 1 ;; esac

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/usr/lib/art" "$WORK/usr/lib/java" "$WORK/usr/include" "$WORK/usr/bin" "$WORK/skia"

# Everything under lib/art that libandroidfw needs at run time, and nothing
# else: no libart.so (about 240 MB), which this vehicle never loads. build.sh
# links empty stubs for the two names art-standalone.pc puts on the link line.
for lib in libandroidfw.so libbase.so libcutils.so liblog.so libutils.so libziparchive.so; do
	cp "$STAGE/lib/art/$lib" "$WORK/usr/lib/art/$lib"
done
cp "$STAGE"/lib/java/*.jar "$WORK/usr/lib/java/"
cp -a "$STAGE"/lib/libglfw.so* "$WORK/usr/lib/"
cp -a "$STAGE/include/androidfw" "$STAGE/include/GLFW" "$WORK/usr/include/"
# atlas's meson resolves `dx` as a program at configure time even though nothing
# here dexes anything; it is a shell wrapper around dx.jar, so it costs nothing.
if [ -f "$STAGE/bin/dx" ]; then cp "$STAGE/bin/dx" "$WORK/usr/bin/dx"; fi

cp -L "$SKIA_LIB" "$WORK/skia/libskia.so"
# include/ plus modules/: atlas only includes headers under include/, but those
# reach into modules/ themselves (SkColorSpace.h -> modules/skcms/skcms.h). The
# rest of the checkout is sources and test data, and is not carried.
cp -aL "$SKIA_SRC/include" "$WORK/skia/include"
cp -aL "$SKIA_SRC/modules" "$WORK/skia/modules"

cat >"$WORK/PROVENANCE.md" <<PROV
# arm64 build-time sysroot for the Fenix click

Packed by \`scripts/make-sysroot.sh\`. Build input only -- nothing here is
shipped in the click except the \`.so\` files \`build.sh\` copies out of
\`usr/lib/art\` and \`skia/libskia.so\`.

| | |
| --- | --- |
| staged sysroot | \`$STAGE\` |
| skia headers | \`$SKIA_SRC\` |
| libskia.so | \`$SKIA_LIB\` |
| packed | $(date -u +%Y-%m-%dT%H:%M:%SZ) |

| Here | What needs it |
| --- | --- |
| usr/lib/art/*.so | libtranslation_layer_main.so's DT_NEEDED and their own |
| usr/lib/java/*.jar | javac's -bootclasspath for the framework (ART's libcore) |
| usr/lib/libglfw.so* + include/GLFW | atlas's window and input backend |
| usr/include/androidfw | headers for libandroidfw |
| usr/bin/dx | atlas's configure-time program lookup only |
| skia/ | libskia.so for the target plus the headers atlas compiles against |

One caveat travels with the skia build: if it was made with
\`skia_use_system_libjpeg_turbo=true\`, sampled JPEG decodes segfault in
\`SkJpegCodec::onGetScaledDimensions\` on libjpeg-turbo 3.x. Rebuilding skia for
aarch64 with atlas's own gn args is the fix.
PROV

mkdir -p "$(dirname "$OUT")"
tar -C "$WORK" -c . | zstd -T0 "-${FENIX_ZSTD_LEVEL:-19}" -o "$OUT" -f
# Relative name, so the file is checkable with `sha256sum -c` next to the
# tarball rather than only at the path it was packed at.
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" | tee "$(basename "$OUT").sha256" )
echo "sysroot: $(du -h "$OUT" | cut -f1)"
