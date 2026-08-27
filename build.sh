#!/bin/bash
# Custom clickable builder for the Ubuntu Touch click of Fenix on OpenJDK.
#
# Runs inside a CROSS clickable container (amd64 host toolchain, aarch64 target
# sysroot). Nothing is compiled by an emulated arm64 toolchain, which is what
# keeps a rebuild in minutes rather than hours -- there is no art_standalone to
# build here, because this vehicle runs the app on a stock JVM, not on ART.
#
# Where each piece comes from:
#
#   built here, arm64          atlas (the HotSpot launcher, libtranslation_layer
#                              _main.so, libandroid.so.0) from the atl-touch
#                              submodule; libportshim.so from shim/
#   built here, portable       hax.jar and framework-res.apk (javac and aapt are
#                              host tools) and shim.jar
#   sysroot tarball            what atlas links against and cannot be cross-
#                              built: art_standalone's libandroidfw and friends
#                              plus their headers, ART's boot jars, GLFW and a
#                              prebuilt libskia.so. See scripts/make-sysroot.sh.
#   payload tarball            Gecko (route B: a glibc libxul for aarch64),
#                              Fenix's class path, the resource APK and the
#                              aarch64 megazord. See scripts/make-payload.sh.
#   container                  the arm64 OpenJDK 21, jlinked into jvm/.
#   fetched                    JNA's linux-aarch64 libjnidispatch.so.
#
# Every stage is stamped in $BUILD_DIR/stamps, so a re-run only redoes what
# changed, and the stamps carry the input's revision or checksum so a stale CI
# cache can never mask a bump.
set -euo pipefail

ROOT="${ROOT:?not run through clickable}"
BUILD_DIR="${BUILD_DIR:?}"
INSTALL_DIR="${INSTALL_DIR:?}"
ARCH="${ARCH:-arm64}"
JOBS="${NUM_PROCS:-$(nproc)}"

PKG="fenix.thekit"
HOOK="fenix"

[ "$ARCH" = "arm64" ] ||
	{ echo "this package is arm64 only (ARCH=$ARCH)" >&2; exit 1; }

TRIPLE="aarch64-linux-gnu"
STAGE="$BUILD_DIR/stage"
PREFIX="$STAGE/usr"              # build-time sysroot for atlas
DL="$BUILD_DIR/downloads"
STAMPS="$BUILD_DIR/stamps"
OUT="$BUILD_DIR/out"             # what this build produces, before assembly
SYSROOT_DIR="$BUILD_DIR/sysroot" # unpacked sysroot tarball
PAYLOAD_DIR="$BUILD_DIR/payload" # unpacked payload tarball
mkdir -p "$PREFIX" "$DL" "$STAMPS" "$OUT"

log()        { echo -e "\033[1;34m[fenix-click]\033[0m $*"; }
stamp()      { [ -f "$STAMPS/$1.done" ]; }
done_stamp() { touch "$STAMPS/$1.done"; }

# --- pinned inputs ----------------------------------------------------------

# The two tarballs this package cannot build itself. Both are GitHub release
# assets of this repository; scripts/make-sysroot.sh and scripts/make-payload.sh
# produce them, README.md says from what.
#
#   FENIX_SYSROOT_TAG / FENIX_PAYLOAD_TAG   the release tag to use
#   FENIX_SYSROOT_SHA256 / FENIX_PAYLOAD_SHA256   optional, verified when set
#   FENIX_ASSET_REPO                        where to fetch them from
#
# A directory named by FENIX_SYSROOT_DIR / FENIX_PAYLOAD_DIR is used as-is
# instead, which is how a local build iterates without publishing anything.
FENIX_ASSET_REPO="${FENIX_ASSET_REPO:-NotKit/fenix-click-packaging}"
FENIX_SYSROOT_TAG="${FENIX_SYSROOT_TAG:-sysroot-1}"
FENIX_PAYLOAD_TAG="${FENIX_PAYLOAD_TAG:-payload-1}"
FENIX_SYSROOT_SHA256="${FENIX_SYSROOT_SHA256:-}"
FENIX_PAYLOAD_SHA256="${FENIX_PAYLOAD_SHA256:-}"

# JNA ships the desktop natives the class path's own jar (an AAR classes.jar)
# does not carry. The version must be the one the class path was built against.
JNA_VERSION="${JNA_VERSION:-5.18.1}"
JNA_SHA256="${JNA_SHA256:-}"

fetch() { # fetch <url> <outfile> [sha256]
	local url="$1" out="$DL/$2" sha="${3:-}"
	if [ -f "$out" ]; then
		[ -n "$sha" ] || return 0
		if echo "$sha  $out" | sha256sum -c - >/dev/null 2>&1; then return 0; fi
	fi
	log "downloading $2"
	curl -Lf --retry 3 -o "$out.tmp" "$url"
	[ -z "$sha" ] || echo "$sha  $out.tmp" | sha256sum -c -
	mv "$out.tmp" "$out"
}

unpack_asset() { # unpack_asset <name> <tag> <sha256> <destdir> <marker>
	local name="$1" tag="$2" sha="$3" dest="$4" marker="$5"
	local file="fenix-jvm-${name}-${ARCH}.tar.zst"
	local archive="$DL/${tag}-${file}"
	if [ ! -f "$archive" ]; then
		local url="https://github.com/${FENIX_ASSET_REPO}/releases/download/${tag}/${file}"
		log "downloading ${name} ${tag}"
		curl -Lf --retry 3 -o "$archive.tmp" "$url" || {
			rm -f "$archive.tmp"
			echo "cannot fetch $url" >&2
			echo "publish it with scripts/make-${name}.sh, or point FENIX_$(echo "$name" | tr a-z A-Z)_DIR at a staged tree" >&2
			exit 1
		}
		mv "$archive.tmp" "$archive"
	fi
	if [ -n "$sha" ]; then
		echo "$sha  $archive" | sha256sum -c - ||
			{ echo "${name} ${tag} checksum mismatch" >&2; exit 1; }
	fi
	rm -rf "$dest"; mkdir -p "$dest"
	zstd -dc "$archive" | tar -C "$dest" -x
	[ -e "$dest/$marker" ] ||
		{ echo "${name} tarball has no $marker" >&2; exit 1; }
}

# --- 1. the build-time sysroot ----------------------------------------------
# atlas resolves art-standalone and glfw3 through pkg-config, links against the
# staged .so files and compiles against their headers.

if [ -n "${FENIX_SYSROOT_DIR:-}" ]; then
	log "sysroot: using $FENIX_SYSROOT_DIR"
	SYSROOT_DIR="$FENIX_SYSROOT_DIR"
	sysroot_id="local-$(sha256sum "$SYSROOT_DIR/PROVENANCE.md" 2>/dev/null | cut -c1-12)"
else
	sysroot_id="$FENIX_SYSROOT_TAG"
	stamp "sysroot-$sysroot_id" ||
		unpack_asset sysroot "$FENIX_SYSROOT_TAG" "${FENIX_SYSROOT_SHA256:-}" \
			"$SYSROOT_DIR" "usr/lib/art/libandroidfw.so"
fi

if ! stamp "prefix-$sysroot_id"; then
	log "staging the build-time sysroot in $PREFIX"
	rsync -a --delete-after "$SYSROOT_DIR/usr/" "$PREFIX/"

	# art-standalone.pc puts -lart -lnativebridge on every link line that uses
	# it. Nothing on this vehicle calls into either -- libtranslation_layer_main
	# .so's DT_NEEDED are libandroidfw and liblog -- so an empty .so of each
	# satisfies the linker and --as-needed drops it again, instead of carrying
	# 240 MB of an ART this click will never load.
	#
	# The four bionic_translation names are the same story one step further:
	# atlas's meson calls cc.find_library('c_bio'/'dl_bio') at configure time,
	# and the HotSpot launcher's glibc_compat.c defines the handful of bionic_*
	# symbols it actually needs itself.
	mkdir -p "$PREFIX/lib/art"
	for stub in art nativebridge; do
		"$TRIPLE-gcc" -shared -o "$PREFIX/lib/art/lib$stub.so" -x c /dev/null
	done
	for stub in c_bio dl_bio; do
		[ -e "$PREFIX/lib/lib$stub.so" ] ||
			"$TRIPLE-gcc" -shared -o "$PREFIX/lib/lib$stub.so" -x c /dev/null
	done

	mkdir -p "$PREFIX/lib/pkgconfig"
	cat >"$PREFIX/lib/pkgconfig/art-standalone.pc" <<EOF
# Generated by build.sh for the arm64 cross build.
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: art-standalone
Description: ART support libraries (libandroidfw and its own; see PROVENANCE.md)
Version: 0.0.0
Libs: -L\${libdir}/art -lart -lnativebridge -landroidfw
Cflags: -I\${includedir} -I\${includedir}/androidfw
EOF
	cat >"$PREFIX/lib/pkgconfig/glfw3.pc" <<EOF
# Generated by build.sh for the arm64 cross build.
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: GLFW
Description: GLFW 3.4 (prebuilt; noble ships 3.3 and atlas needs the libdecor init hint)
Version: 3.4
Libs: -L\${libdir} -lglfw
Cflags: -I\${includedir}
EOF
	# atlas's meson resolves `dx` as a program at configure time even though
	# nothing on this vehicle dexes anything; it looks for dx.jar in
	# ../framework relative to its own bin/ first.
	if [ -f "$PREFIX/lib/java/dx.jar" ]; then
		mkdir -p "$PREFIX/framework"
		cp "$PREFIX/lib/java/dx.jar" "$PREFIX/framework/dx.jar"
	fi
	done_stamp "prefix-$sysroot_id"
	done_stamp "sysroot-$sysroot_id"
fi

export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

HOST_JAVA_HOME="${HOST_JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
TARGET_JAVA_HOME="${TARGET_JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-arm64}"
[ -x "$HOST_JAVA_HOME/bin/javac" ] ||
	{ echo "no host JDK 21 at $HOST_JAVA_HOME (openjdk-21-jdk-headless)" >&2; exit 1; }
[ -f "$TARGET_JAVA_HOME/lib/server/libjvm.so" ] ||
	{ echo "no arm64 JVM at $TARGET_JAVA_HOME (openjdk-21-jdk-headless:arm64)" >&2; exit 1; }
export JAVA_HOME="$HOST_JAVA_HOME"

# --- 2. atlas ---------------------------------------------------------------

ATLAS_SRC="$ROOT/atl-touch"
ATLAS_BUILD="$BUILD_DIR/atlas-build"
[ -f "$ATLAS_SRC/meson.build" ] ||
	{ echo "no atl-touch checkout: git submodule update --init --remote" >&2; exit 1; }

CROSS_FILE="$BUILD_DIR/meson-cross.ini"
CC="$TRIPLE-gcc" CXX="$TRIPLE-g++" AR="$TRIPLE-ar" STRIP="$TRIPLE-strip" \
PKG_CONFIG="$TRIPLE-pkg-config" \
CROSS_LIB_DIRS="$PREFIX/lib $PREFIX/lib/art" CROSS_INCLUDE_DIRS="$PREFIX/include" \
HOST_JAVA_HOME="$HOST_JAVA_HOME" TARGET_JAVA_HOME="$TARGET_JAVA_HOME" \
	"$ROOT/scripts/write-meson-cross.sh" "$CROSS_FILE"

# -Dskia-prebuilt: skia's gn build is not driven from atlas's meson and does not
# cross-compile from it, so a ready-made libskia.so is linked instead. This is
# atlas's own option, written for exactly this.
# The prefix only decides what atlas bakes into its RUNPATHs and INSTALL_DATADIR.
# The click's layout is flat (everything native in lib/), so nothing is actually
# installed there and run.sh's LD_LIBRARY_PATH is what resolves the libraries;
# the version-independent 'current' path is used anyway, so a baked-in path is
# at worst inert rather than wrong.
SETUP_ARGS=(
	--cross-file "$CROSS_FILE"
	--buildtype=release --libdir=lib
	--prefix="/opt/click.ubuntu.com/$PKG/current/usr"
	-Dskia-prebuilt="$SYSROOT_DIR/skia"
	-Dhotspot-launcher=enabled
	-Dimage-launcher=disabled
)
# The JDK and the cross file are baked into meson's coredata, so a change to
# either needs a from-scratch configure rather than --reconfigure.
setup_id="$(printf '%s' "${SETUP_ARGS[*]} $HOST_JAVA_HOME $TARGET_JAVA_HOME" | sha256sum | cut -c1-12)"
if [ ! -f "$ATLAS_BUILD/build.ninja" ]; then
	log "configuring atlas ($TRIPLE, prebuilt skia)"
	meson setup "${SETUP_ARGS[@]}" "$ATLAS_BUILD" "$ATLAS_SRC"
	printf '%s' "$setup_id" >"$ATLAS_BUILD/.setup-id"
elif [ "$(cat "$ATLAS_BUILD/.setup-id" 2>/dev/null)" != "$setup_id" ]; then
	log "atlas was configured differently, wiping"
	meson setup --wipe "${SETUP_ARGS[@]}" "$ATLAS_BUILD" "$ATLAS_SRC"
	printf '%s' "$setup_id" >"$ATLAS_BUILD/.setup-id"
fi

ATLAS_TARGETS=(
	android-translation-layer-hotspot
	libtranslation_layer_main.so
	libandroid.so.0
	src/api-impl/hax.jar
	res/framework-res/framework-res.apk
)
log "building atlas ($(git -C "$ATLAS_SRC" rev-parse --short HEAD 2>/dev/null || echo '?'))"
ninja -C "$ATLAS_BUILD" -j"$JOBS" "${ATLAS_TARGETS[@]}"

# hax.jar, not hax-stripped.jar and not api-impl.jar. api-impl.jar is
# hax-stripped.jar run through `dx --dex` and holds nothing but a classes.dex,
# which HotSpot cannot read; hax-stripped.jar drops three compile-only stubs
# because ART rejects an app's oat file when a class is defined twice, and a JVM
# class path has no such check -- Fenix's own activity needs one of the three
# (OnBackInvokedCallback) at load time.
for f in "${ATLAS_TARGETS[@]}"; do
	[ -e "$ATLAS_BUILD/$f" ] || { echo "atlas produced no $f" >&2; exit 1; }
done

# --- 3. the libcore/dalvik compat shim --------------------------------------

shim_id="$(find "$ROOT/shim/src" "$ROOT/shim/native" "$ROOT/shim/resources" -type f | sort | xargs cat | sha256sum | cut -c1-12)"
if ! stamp "shim-$shim_id"; then
	log "building the compat shim"
	JAVA_HOME="$HOST_JAVA_HOME" JNI_JAVA_HOME="$TARGET_JAVA_HOME" \
	CC="$TRIPLE-gcc" NM="$TRIPLE-nm" "$ROOT/shim/build.sh" "$OUT"
	done_stamp "shim-$shim_id"
fi

# --- 4. the payload: Gecko, the class path, the resource APK, the megazord ---

if [ -n "${FENIX_PAYLOAD_DIR:-}" ]; then
	log "payload: using $FENIX_PAYLOAD_DIR"
	PAYLOAD_DIR="$FENIX_PAYLOAD_DIR"
else
	stamp "payload-$FENIX_PAYLOAD_TAG" ||
		unpack_asset payload "$FENIX_PAYLOAD_TAG" "${FENIX_PAYLOAD_SHA256:-}" \
			"$PAYLOAD_DIR" "gecko/libxul.so"
	done_stamp "payload-$FENIX_PAYLOAD_TAG"
fi
for f in gecko/libxul.so gecko/libmozglue.so fenix.apk classpath natives/megazord/libmegazord.so; do
	[ -e "$PAYLOAD_DIR/$f" ] || { echo "payload has no $f" >&2; exit 1; }
done
jar_count=$(find "$PAYLOAD_DIR/classpath" -maxdepth 1 -name '*.jar' | wc -l)
[ "$jar_count" -ge 100 ] ||
	{ echo "only $jar_count jars in the payload's classpath" >&2; exit 1; }

# --- 5. JNA's native --------------------------------------------------------
# The class path's jna jar is an AAR classes.jar and carries no natives at all;
# without libjnidispatch every uniffi binding fails in Native.register before
# the first frame. Stock upstream JNA, the version the class path pins.

if ! stamp "jna-$JNA_VERSION"; then
	fetch "https://repo1.maven.org/maven2/net/java/dev/jna/jna/${JNA_VERSION}/jna-${JNA_VERSION}.jar" \
		"jna-${JNA_VERSION}.jar" "$JNA_SHA256"
	rm -rf "$OUT/jna"; mkdir -p "$OUT/jna"
	unzip -o -j "$DL/jna-${JNA_VERSION}.jar" \
		'com/sun/jna/linux-aarch64/libjnidispatch.so' -d "$OUT/jna" >/dev/null
	[ -f "$OUT/jna/libjnidispatch.so" ] ||
		{ echo "jna-${JNA_VERSION}.jar has no linux-aarch64/libjnidispatch.so" >&2; exit 1; }
	done_stamp "jna-$JNA_VERSION"
fi

# --- 6. assemble the click tree ---------------------------------------------

log "assembling $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,atlas,classpath,gecko}

# One flat directory for every native object, launcher included: atlas's natives
# find each other through their $ORIGIN/ RUNPATH, and the absolute paths this
# build baked into them do not exist on the device.
cp "$ATLAS_BUILD/android-translation-layer-hotspot" "$INSTALL_DIR/lib/"
cp "$ATLAS_BUILD/libtranslation_layer_main.so" "$ATLAS_BUILD/libandroid.so.0" "$INSTALL_DIR/lib/"
ln -sfn libandroid.so.0 "$INSTALL_DIR/lib/libandroid.so"
cp "$SYSROOT_DIR/skia/libskia.so" "$INSTALL_DIR/lib/"
cp "$OUT/libportshim.so" "$INSTALL_DIR/lib/"
cp "$OUT/jna/libjnidispatch.so" "$INSTALL_DIR/lib/"
cp "$PAYLOAD_DIR/natives/megazord/libmegazord.so" "$INSTALL_DIR/lib/"

# What libtranslation_layer_main.so links and Ubuntu Touch does not ship: art's
# libandroidfw and its own dependencies, and GLFW 3.4.
cp "$PREFIX"/lib/art/*.so "$INSTALL_DIR/lib/"
rm -f "$INSTALL_DIR/lib/libart.so" "$INSTALL_DIR/lib/libnativebridge.so"  # the stubs
cp -a "$PREFIX"/lib/libglfw.so* "$INSTALL_DIR/lib/"

cp "$ATLAS_BUILD/src/api-impl/hax.jar" "$INSTALL_DIR/atlas/"
cp "$ATLAS_BUILD/res/framework-res/framework-res.apk" "$INSTALL_DIR/atlas/"
# The Roboto faces atlas builds its minikin generic families (sans-serif and its
# weight aliases) from. Without them the framework asks fontconfig, which hands
# back Ubuntu on this device, and text is laid out with Android's metrics against
# a different font: measured wider, every line taller. run.sh points ATL_FONT_DIR
# here.
#
# Gecko is a separate matter: it reads $ANDROID_ROOT/fonts, which run.sh fills
# from the device's own fonts on first start.
[ -d "$ATLAS_SRC/res/fonts" ] ||
	{ echo "the atl-touch checkout has no res/fonts" >&2; exit 1; }
mkdir -p "$INSTALL_DIR/atlas/system/fonts"
cp "$ATLAS_SRC"/res/fonts/*.ttf "$INSTALL_DIR/atlas/system/fonts/"
for f in NOTICE README.md; do
	[ -f "$ATLAS_SRC/res/fonts/$f" ] || continue
	cp "$ATLAS_SRC/res/fonts/$f" "$INSTALL_DIR/atlas/system/fonts/"
done
log "bundled $(ls "$INSTALL_DIR"/atlas/system/fonts/*.ttf | wc -l) Roboto faces"

cp "$OUT/shim.jar" "$INSTALL_DIR/classpath/"
cp "$PAYLOAD_DIR"/classpath/*.jar "$INSTALL_DIR/classpath/"

# Gecko, whole: libxul and the NSS set, omni.ja's siblings (chrome/, components/,
# modules/, ...) and libmozglue.so. libmozglue stays *inside* gecko/ on purpose:
# GeckoLoader putenvs MOZ_ANDROID_LIBDIR from wherever it found it and APKOpen
# dlopens libnss3/libnspr4/libplc4/libmozsqlite3 out of that same directory.
rsync -a "$PAYLOAD_DIR/gecko/" "$INSTALL_DIR/gecko/"

# The resource container. Its dex and its lib/ are inert on a JVM class path;
# atlas's AssetManager finds it by scanning for a zip holding an
# AndroidManifest.xml, and PackageParser reads that manifest as AAPT binary XML.
cp "$PAYLOAD_DIR/fenix.apk" "$INSTALL_DIR/fenix.apk"

install -m 0755 "$ROOT/run.sh" "$INSTALL_DIR/run.sh"
install -m 0644 "$ROOT/user.js" "$INSTALL_DIR/user.js"
cp "$ROOT/$HOOK.desktop" "$ROOT/$HOOK.apparmor" "$ROOT/$HOOK.svg" "$INSTALL_DIR/"

# clickable fills in @CLICK_ARCH@ and @CLICK_FRAMEWORK@; the version comes from
# the payload, so a click is identifiable as the Gecko build inside it.
app_version="$(sed -n 's/^version=//p' "$PAYLOAD_DIR/PAYLOAD.txt" 2>/dev/null | head -1)"
sed "s|@CLICK_VERSION@|${app_version:-0.0.0}|" "$ROOT/manifest.json" \
	>"$INSTALL_DIR/manifest.json"

# --- 7. the JVM -------------------------------------------------------------
# A jlink image of the modules the app reaches, not a copy of the whole JDK
# (about 210 MB down to about 75 MB). jlink is architecture-neutral, so the
# host's builds the arm64 image out of the arm64 jmods and the cross build stays
# a cross build. It also writes real files where Debian's JDK is a tree of
# symlinks into /etc/java-21-openjdk and /etc/ssl/certs, none of which exists on
# the device -- including a populated cacerts.
#
# Re-derive the module set when a dependency is added:
#   jdeps --ignore-missing-deps --print-module-deps --multi-release 21 \
#         -cp 'classpath/*:atlas/hax.jar' classpath/*.jar atlas/hax.jar
# and keep it generous: a missing module is not a build error, it is a
# NoClassDefFoundError on whatever path first needs it.
JVM_MODULES="java.base,java.compiler,java.desktop,java.instrument,java.logging"
JVM_MODULES="$JVM_MODULES,java.management,java.naming,java.net.http,java.prefs"
JVM_MODULES="$JVM_MODULES,java.scripting,java.sql,java.xml,java.xml.crypto"
JVM_MODULES="$JVM_MODULES,jdk.charsets,jdk.crypto.ec,jdk.jdwp.agent,jdk.localedata"
JVM_MODULES="$JVM_MODULES,jdk.unsupported,jdk.zipfs"

[ -d "$TARGET_JAVA_HOME/jmods" ] || {
	echo "no jmods at $TARGET_JAVA_HOME -- jlink needs them and the jre package has none" >&2
	exit 1
}
# jlink refuses jmods from another JDK build.
host_build=$(sed -n 's/^JAVA_VERSION="\(.*\)"/\1/p' "$HOST_JAVA_HOME/release")
target_build=$(sed -n 's/^JAVA_VERSION="\(.*\)"/\1/p' "$TARGET_JAVA_HOME/release")
[ "$host_build" = "$target_build" ] || {
	echo "JDK mismatch: host jlink is $host_build, arm64 jmods are $target_build" >&2
	exit 1
}

log "jlinking the arm64 JVM"
rm -rf "$INSTALL_DIR/jvm"
"$HOST_JAVA_HOME/bin/jlink" \
	--module-path "$TARGET_JAVA_HOME/jmods" \
	--add-modules "$JVM_MODULES" \
	--no-header-files --no-man-pages --compress=zip-6 \
	--output "$INSTALL_DIR/jvm"
# libjvm.so is the launcher's DT_NEEDED and the JVM derives java.home from where
# it was loaded from, so this one file decides whether the image is usable.
[ -f "$INSTALL_DIR/jvm/lib/server/libjvm.so" ] ||
	{ echo "jlink produced no lib/server/libjvm.so" >&2; exit 1; }
log "  JVM image: $(du -sh "$INSTALL_DIR/jvm" | cut -f1)"

# The class-path archive (AppCDS) is NOT built here and NOT shipped: HotSpot
# records each entry's size and mtime, so an archive made against this build
# tree would be stale the moment the click is installed. run.sh creates one on
# the device, in the cache directory, with -XX:+AutoCreateSharedArchive.

# --- 8. bundle what the device does not have --------------------------------
# device-libs.txt is the device's own `ldconfig -p`. Anything the click needs
# that is not there travels with it. Closure, because a bundled library brings
# its own DT_NEEDED.

device_libs="$ROOT/device-libs.txt"
[ -f "$device_libs" ] || { echo "missing $device_libs" >&2; exit 1; }
search_dirs=("/usr/lib/$TRIPLE" "/lib/$TRIPLE" "$PREFIX/lib" "$PREFIX/lib/art")
unavailable=""
while :; do
	needed=$(find "$INSTALL_DIR/lib" "$INSTALL_DIR/gecko" -type f \
			\( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) 2>/dev/null |
		while read -r f; do
			readelf -d "$f" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'
		done | sort -u)
	# The JVM's own libraries count as present: run.sh puts jvm/lib/server on
	# LD_LIBRARY_PATH. So does gecko/, which carries NSS and mozglue.
	have=$( { ls "$INSTALL_DIR/lib"
		  find "$INSTALL_DIR/gecko" -name '*.so*' -printf '%f\n' 2>/dev/null
		  find "$INSTALL_DIR/jvm" -name '*.so' -printf '%f\n' 2>/dev/null
		  echo "$unavailable"
		  grep -v '^#' "$device_libs"; } | sort -u)
	missing=$(comm -23 <(echo "$needed") <(echo "$have"))
	[ -n "$missing" ] || break
	for lib in $missing; do
		found=""
		for d in "${search_dirs[@]}"; do
			if [ -e "$d/$lib" ]; then
				cp -L "$d/$lib" "$INSTALL_DIR/lib/$lib"; found=1; break
			fi
		done
		if [ -n "$found" ]; then
			log "  bundling $lib (not on the device)"
		else
			echo "  WARNING: $lib is neither on the device nor in this container" >&2
			unavailable="$unavailable$lib"$'\n'
		fi
	done
done
[ -z "$unavailable" ] || {
	echo "unresolvable libraries -- the app would fail to start:" >&2
	echo "$unavailable" >&2
	exit 1
}

# The four stubs exist only to satisfy a link line; $PREFIX/lib is on the search
# path above, so a real DT_NEEDED on one of them would be "resolved" by shipping
# an empty .so and the failure would just move to the first call.
for stub in libart.so libnativebridge.so libc_bio.so libdl_bio.so; do
	[ ! -e "$INSTALL_DIR/lib/$stub" ] ||
		{ echo "$stub was bundled -- something links it for real, and the stub is empty" >&2; exit 1; }
done

# --- 9. strip and verify ----------------------------------------------------
# libxul alone is about 290 MB unstripped and about 150 MB stripped, which is
# most of the difference between a click that fits and one that does not.

if [ "${FENIX_SKIP_STRIP:-0}" != 1 ]; then
	log "stripping"
	find "$INSTALL_DIR/lib" "$INSTALL_DIR/gecko" -type f \
		\( -name '*.so' -o -name '*.so.*' \) \
		-exec "$TRIPLE-strip" --strip-unneeded {} + 2>/dev/null || true
	"$TRIPLE-strip" --strip-unneeded "$INSTALL_DIR/lib/android-translation-layer-hotspot" 2>/dev/null || true
fi

log "verifying the staged tree"
bad=0
while read -r f; do
	case "$(file -b "$f")" in
	*"ARM aarch64"*) ;;
	*) echo "  NOT aarch64: $f  ($(file -b "$f" | cut -c1-60))" >&2; bad=1 ;;
	esac
done < <(find "$INSTALL_DIR/lib" "$INSTALL_DIR/gecko" "$INSTALL_DIR/jvm/lib" "$INSTALL_DIR/jvm/bin" \
	-type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) 2>/dev/null | grep -v '\.jar$')
[ "$bad" = 0 ] || { echo "the click holds objects for the wrong architecture" >&2; exit 1; }

log "click tree staged: $(du -sh "$INSTALL_DIR" | cut -f1)"
