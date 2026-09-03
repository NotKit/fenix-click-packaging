#!/bin/bash
# Custom clickable builder for the Ubuntu Touch click of Fenix on OpenJDK.
#
# Runs inside a clickable container, and compiles almost nothing: the two big
# inputs are prebuilt tarballs, so a rebuild is minutes.
#
# Where each piece comes from:
#
#   SDK tarball                atlas itself -- the HotSpot launcher,
#                              libtranslation_layer_main.so, libandroid.so.0,
#                              api-impl_classes.jar, framework-res.apk, the
#                              Roboto faces -- plus everything it links that
#                              Ubuntu Touch does not ship: art_standalone's
#                              libandroidfw and friends, GLFW 3.4 and libskia.
#                              Built by atl-touch's own CI (ci/build-sdk.sh) on
#                              a native arm64 runner and published per commit.
#   payload tarball            Gecko (a glibc libxul for aarch64),
#                              Fenix's class path, the resource APK and the
#                              aarch64 megazord. See scripts/make-payload.sh.
#   built here                 shim.jar and libportshim.so, from shim/.
#   container                  the arm64 OpenJDK 21, jlinked into jvm/.
#   fetched                    JNA's linux-aarch64 libjnidispatch.so.
#
# The framework jar is api-impl_classes.jar and NOT the api-impl.jar beside it
# under lib/java/dex: that one is the same classes run through d8 and holds
# nothing but a classes.dex, which HotSpot cannot read. It is also the
# unstripped jar -- the stripped one drops three compile-only stubs because ART
# rejects a class defined twice, and Fenix's own activity needs one of them
# (OnBackInvokedCallback) at load time.
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
DL="$BUILD_DIR/downloads"
STAMPS="$BUILD_DIR/stamps"
OUT="$BUILD_DIR/out"             # what this build produces, before assembly
SDK_DIR="$BUILD_DIR/sdk"         # unpacked SDK tarball (atlas + its runtime)
PAYLOAD_DIR="$BUILD_DIR/payload" # unpacked payload tarball
mkdir -p "$DL" "$STAMPS" "$OUT"

log()        { echo -e "\033[1;34m[fenix-click]\033[0m $*"; }
stamp()      { [ -f "$STAMPS/$1.done" ]; }
done_stamp() { touch "$STAMPS/$1.done"; }

# --- pinned inputs ----------------------------------------------------------

# The two tarballs this package does not build itself.
#
#   the SDK      atlas and its native chain, a release asset of NotKit/atl-touch
#                (its ci/build-sdk.sh builds it on a native arm64 runner)
#   the payload  Gecko and Fenix's class path, a release asset of this
#                repository (.github/workflows/payload.yml, scripts/make-payload.sh)
#
#   FENIX_SDK_TAG / FENIX_PAYLOAD_TAG           the release tag to use
#   FENIX_SDK_SHA256 / FENIX_PAYLOAD_SHA256     optional, verified when set
#   FENIX_SDK_REPO / FENIX_ASSET_REPO           where to fetch each from
#
# A directory named by FENIX_SDK_DIR / FENIX_PAYLOAD_DIR is used as-is instead,
# which is how a local build iterates without publishing anything.
FENIX_ASSET_REPO="${FENIX_ASSET_REPO:-NotKit/fenix-click-packaging}"
FENIX_SDK_REPO="${FENIX_SDK_REPO:-NotKit/atl-touch}"
FENIX_SDK_TAG="${FENIX_SDK_TAG:-sdk-0fb6e4d}"
FENIX_SDK_SHA256="${FENIX_SDK_SHA256:-9ee318ed727e217a929a486b907014b73742a74bfce4563003420fbb340d182f}"
FENIX_PAYLOAD_TAG="${FENIX_PAYLOAD_TAG:-payload-20260829-ga33881773531}"
FENIX_PAYLOAD_SHA256="${FENIX_PAYLOAD_SHA256:-45034c037f19a7a0e1bdb3f416b295150f6a8fb317465197d9c8fbead5162c07}"

# Which vehicle this click carries. The two are separate clicks under the same
# package name, so a device holds one at a time and installing the other is an
# upgrade: the profile in ~/.local/share survives it.
#
#   image    the ahead-of-time image alone -- no JVM, no jars, no CDS
#   hotspot  the JVM, the jars and the base CDS archive alone
#   both     one click that carries either, which is what a local build wants
#
# clickable does not forward the host environment into its container, so CI
# picks the vehicle by writing .vehicle into the repo, the same bind mount
# prebuilt/image arrives through. An env var wins when there is one, which is
# how a container-mode or direct run selects it.
FENIX_VEHICLE="${FENIX_VEHICLE:-$(cat "$ROOT/.vehicle" 2>/dev/null || echo both)}"
case "$FENIX_VEHICLE" in
image | hotspot | both) ;;
*) echo "FENIX_VEHICLE must be image, hotspot or both, not $FENIX_VEHICLE" >&2; exit 1 ;;
esac

# What to repackage out of the resource APK, as strip-apk.py's --drop sets.
# Empty ships it whole. See the APK staging step for why omni is not in here.
FENIX_APK_STRIP="${FENIX_APK_STRIP-dex,sig,lib}"

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

unpack_asset() { # unpack_asset <name> <repo> <file> <tag> <sha256> <destdir> <marker>
	local name="$1" repo="$2" file="$3" tag="$4" sha="$5" dest="$6" marker="$7"
	local archive="$DL/${tag}-${file}"
	if [ ! -f "$archive" ]; then
		local url="https://github.com/${repo}/releases/download/${tag}/${file}"
		log "downloading ${name} ${tag}"
		curl -Lf --retry 3 -o "$archive.tmp" "$url" || {
			rm -f "$archive.tmp"
			echo "cannot fetch $url" >&2
			echo "point FENIX_$(echo "$name" | tr a-z A-Z)_DIR at a staged tree to build without it" >&2
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

# --- 1. the SDK: atlas and everything it links ------------------------------
# Prebuilt by atl-touch's CI on a native arm64 runner. Nothing here is compiled
# or configured -- the tree is unpacked and read.

if [ -n "${FENIX_SDK_DIR:-}" ]; then
	log "sdk: using $FENIX_SDK_DIR"
	SDK_DIR="$FENIX_SDK_DIR"
else
	stamp "sdk-$FENIX_SDK_TAG" ||
		unpack_asset sdk "$FENIX_SDK_REPO" "atl-sdk-${ARCH}.tar.zst" \
			"$FENIX_SDK_TAG" "$FENIX_SDK_SHA256" \
			"$SDK_DIR" "usr/lib/java/api-impl_classes.jar"
	done_stamp "sdk-$FENIX_SDK_TAG"
fi

ATL="$SDK_DIR/usr"
ATL_DEX="$ATL/lib/java/dex/android_translation_layer"   # framework-res.apk
ATL_NATIVES="$ATL_DEX/natives"                          # libtranslation_layer_main.so
for f in bin/android-translation-layer-hotspot \
	 lib/libandroid.so.0 lib/libskia.so lib/art/libandroidfw.so \
	 lib/java/api-impl_classes.jar \
	 lib/java/dex/android_translation_layer/framework-res.apk \
	 lib/java/dex/android_translation_layer/natives/libtranslation_layer_main.so \
	 share/atl/system/fonts; do
	[ -e "$ATL/$f" ] || { echo "the SDK has no $f" >&2; exit 1; }
done
log "sdk: $FENIX_SDK_TAG, atlas $(sed -n 's/.*"atlas": "\(.*\)".*/\1/p' "$SDK_DIR/meta/sdk-manifest.json" 2>/dev/null | cut -c1-12)"

HOST_JAVA_HOME="${HOST_JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
TARGET_JAVA_HOME="${TARGET_JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-arm64}"
[ -x "$HOST_JAVA_HOME/bin/javac" ] ||
	{ echo "no host JDK 21 at $HOST_JAVA_HOME (openjdk-21-jdk-headless)" >&2; exit 1; }
[ -f "$TARGET_JAVA_HOME/lib/server/libjvm.so" ] ||
	{ echo "no arm64 JVM at $TARGET_JAVA_HOME (openjdk-21-jdk-headless:arm64)" >&2; exit 1; }
export JAVA_HOME="$HOST_JAVA_HOME"

# --- 2. the libcore/dalvik compat shim --------------------------------------

shim_id="$(find "$ROOT/shim/src" "$ROOT/shim/native" "$ROOT/shim/resources" -type f | sort | xargs cat | sha256sum | cut -c1-12)"
if ! stamp "shim-$shim_id"; then
	log "building the compat shim"
	JAVA_HOME="$HOST_JAVA_HOME" JNI_JAVA_HOME="$TARGET_JAVA_HOME" \
	CC="$TRIPLE-gcc" NM="$TRIPLE-nm" "$ROOT/shim/build.sh" "$OUT"
	done_stamp "shim-$shim_id"
fi

# --- 3. the payload: Gecko, the class path, the resource APK, the megazord ---

if [ -n "${FENIX_PAYLOAD_DIR:-}" ]; then
	log "payload: using $FENIX_PAYLOAD_DIR"
	PAYLOAD_DIR="$FENIX_PAYLOAD_DIR"
else
	stamp "payload-$FENIX_PAYLOAD_TAG" ||
		unpack_asset payload "$FENIX_ASSET_REPO" "fenix-jvm-payload-${ARCH}.tar.zst" \
			"$FENIX_PAYLOAD_TAG" "${FENIX_PAYLOAD_SHA256:-}" \
			"$PAYLOAD_DIR" "gecko/libxul.so"
	done_stamp "payload-$FENIX_PAYLOAD_TAG"
fi
for f in gecko/libxul.so gecko/libmozglue.so fenix.apk classpath natives/megazord/libmegazord.so; do
	[ -e "$PAYLOAD_DIR/$f" ] || { echo "payload has no $f" >&2; exit 1; }
done
jar_count=$(find "$PAYLOAD_DIR/classpath" -maxdepth 1 -name '*.jar' | wc -l)
[ "$jar_count" -ge 100 ] ||
	{ echo "only $jar_count jars in the payload's classpath" >&2; exit 1; }

# --- 4. JNA's native --------------------------------------------------------
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

# --- 4b. the native image, when one is pinned -------------------------------
# Fenix's whole class path compiled ahead of time into a shared library that
# exports the JNI Invocation API, built by the image job in
# .github/workflows/build.yml on an arm64 runner, since native-image cannot
# cross-compile. It is an *addition*: the click still ships the JVM and the
# jars, and run.sh takes FENIX_VM=image to start atlas's image launcher
# instead of the HotSpot one.
#
# Where it comes from, in order:
#   FENIX_IMAGE_DIR   an explicit directory, for running build.sh directly
#   prebuilt/image    where CI's image job leaves its artifact. clickable does
#                     not forward the environment into its container, so the
#                     path cannot be passed in; the repo bind mount is how it
#                     gets here.
#   FENIX_IMAGE_TAG   a published image, for building on a machine that cannot
#                     make one. Empty by default: a pinned tag has to be bumped
#                     in lockstep with the SDK, which made every atlas bump two
#                     commits with a failing build in between.
# Nothing found means no image travels and the click is HotSpot-only.
FENIX_IMAGE_TAG="${FENIX_IMAGE_TAG:-}"
FENIX_IMAGE_SHA256="${FENIX_IMAGE_SHA256:-}"
IMAGE_DIR="$BUILD_DIR/image"

if [ "$FENIX_VEHICLE" = hotspot ]; then
	log "vehicle: hotspot only, so no image travels"
	IMAGE_DIR=""
elif [ -n "${FENIX_IMAGE_DIR:-}" ]; then
	log "image: using $FENIX_IMAGE_DIR"
	IMAGE_DIR="$FENIX_IMAGE_DIR"
elif [ -f "$ROOT/prebuilt/image/libfenix.so" ]; then
	log "image: using prebuilt/image"
	IMAGE_DIR="$ROOT/prebuilt/image"
elif [ -n "$FENIX_IMAGE_TAG" ]; then
	stamp "image-$FENIX_IMAGE_TAG" ||
		unpack_asset image "$FENIX_ASSET_REPO" "fenix-image-${ARCH}.tar.zst" \
			"$FENIX_IMAGE_TAG" "$FENIX_IMAGE_SHA256" \
			"$IMAGE_DIR" "libfenix.so"
	done_stamp "image-$FENIX_IMAGE_TAG"
else
	IMAGE_DIR=""
fi

# An image-only click with no image would be a click with no browser in it, and
# the failure is silent: run.sh finds no libfenix.so and falls back to a HotSpot
# that is not there either.
[ "$FENIX_VEHICLE" != image ] || [ -n "$IMAGE_DIR" ] ||
	{ echo "FENIX_VEHICLE=image but no image was found" >&2; exit 1; }

# An image *is* the framework and the class path, compiled: one built against a
# different SDK or payload than this click carries is a different browser, and
# the mismatch would only show as a wrong or missing class at run time.
if [ -n "$IMAGE_DIR" ]; then
	[ -f "$IMAGE_DIR/libfenix.so" ] || { echo "no $IMAGE_DIR/libfenix.so" >&2; exit 1; }
	img_sdk=$(sed -n 's/^sdk=//p' "$IMAGE_DIR/IMAGE.txt" 2>/dev/null)
	img_payload=$(sed -n 's/^payload=//p' "$IMAGE_DIR/IMAGE.txt" 2>/dev/null)
	for pair in "sdk:$img_sdk:$FENIX_SDK_TAG" "payload:$img_payload:$FENIX_PAYLOAD_TAG"; do
		what=${pair%%:*}; rest=${pair#*:}; was=${rest%%:*}; want=${rest#*:}
		[ -z "$was" ] || [ "$was" = "$want" ] ||
			{ echo "the image was built over $what $was, this click ships $want" >&2; exit 1; }
	done
	log "image: ${img_sdk:+over $img_sdk, }${img_payload:+$img_payload}"
fi

# --- 5. assemble the click tree ---------------------------------------------

log "assembling $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,atlas,gecko}
[ "$FENIX_VEHICLE" = image ] || mkdir -p "$INSTALL_DIR/classpath"

# Which vehicle is installed, for anyone holding the phone: both clicks carry
# the same package name and version, so nothing else tells them apart.
echo "vehicle=$FENIX_VEHICLE" >"$INSTALL_DIR/VEHICLE.txt"

# One flat directory for every native object, launcher included: atlas's natives
# find each other through their $ORIGIN/ RUNPATH, and the SDK prefix the rest of
# that RUNPATH names does not exist on the device.
[ "$FENIX_VEHICLE" = image ] ||
	cp "$ATL/bin/android-translation-layer-hotspot" "$INSTALL_DIR/lib/"
if [ -n "$IMAGE_DIR" ]; then
	# The image launcher dlopens the .so instead of linking libjvm.so; both live
	# in lib/ with everything else so $ORIGIN finds them.
	cp "$ATL/bin/android-translation-layer-image" "$INSTALL_DIR/lib/"
	cp "$IMAGE_DIR/libfenix.so" "$INSTALL_DIR/lib/"
	[ ! -f "$IMAGE_DIR/IMAGE.txt" ] || cp "$IMAGE_DIR/IMAGE.txt" "$INSTALL_DIR/"
fi
cp "$ATL_NATIVES/libtranslation_layer_main.so" "$INSTALL_DIR/lib/"
cp -a "$ATL/lib/libandroid.so.0" "$INSTALL_DIR/lib/"
ln -sfn libandroid.so.0 "$INSTALL_DIR/lib/libandroid.so"
cp "$ATL/lib/libskia.so" "$INSTALL_DIR/lib/"
cp -a "$ATL"/lib/libglfw.so* "$INSTALL_DIR/lib/"
cp "$OUT/libportshim.so" "$INSTALL_DIR/lib/"
cp "$OUT/jna/libjnidispatch.so" "$INSTALL_DIR/lib/"
cp "$PAYLOAD_DIR/natives/megazord/libmegazord.so" "$INSTALL_DIR/lib/"

# art's libandroidfw and its own dependencies, by name. Not the whole of the
# SDK's lib/art -- that carries the ART runtime this vehicle never loads -- and
# not left to section 7's closure either: gecko/ ships a liblog.so of its own
# (the shim's six-kilobyte forwarder), the closure would count that as the
# liblog atlas asked for, and atlas would bind the wrong one.
for l in libandroidfw.so liblog.so libbase.so libcutils.so libutils.so libziparchive.so; do
	cp "$ATL/lib/art/$l" "$INSTALL_DIR/lib/$l"
done

[ "$FENIX_VEHICLE" = image ] ||
	cp "$ATL/lib/java/api-impl_classes.jar" "$INSTALL_DIR/atlas/hax.jar"
cp "$ATL_DEX/framework-res.apk" "$INSTALL_DIR/atlas/"
# The Roboto faces atlas builds its minikin generic families (sans-serif and its
# weight aliases) from. Without them the framework asks fontconfig, which hands
# back Ubuntu on this device, and text is laid out with Android's metrics against
# a different font: measured wider, every line taller. run.sh points ATL_FONT_DIR
# here.
#
# Gecko is a separate matter: it reads $ANDROID_ROOT/fonts, which run.sh fills
# from the device's own fonts on first start.
mkdir -p "$INSTALL_DIR/atlas/system/fonts"
cp -a "$ATL"/share/atl/system/fonts/. "$INSTALL_DIR/atlas/system/fonts/"
log "bundled $(ls "$INSTALL_DIR"/atlas/system/fonts/*.ttf | wc -l) Roboto faces"

# The jars, for the vehicle that loads jars. libportshim.so is not among them:
# both vehicles dlopen it, so it is copied with the other natives above.
if [ "$FENIX_VEHICLE" != image ]; then
	cp "$OUT/shim.jar" "$INSTALL_DIR/classpath/"
	cp "$PAYLOAD_DIR"/classpath/*.jar "$INSTALL_DIR/classpath/"
fi

# Gecko, whole: libxul and the NSS set, omni.ja's siblings (chrome/, components/,
# modules/, ...) and libmozglue.so. libmozglue stays *inside* gecko/ on purpose:
# GeckoLoader putenvs MOZ_ANDROID_LIBDIR from wherever it found it and APKOpen
# dlopens libnss3/libnspr4/libplc4/libmozsqlite3 out of that same directory.
rsync -a "$PAYLOAD_DIR/gecko/" "$INSTALL_DIR/gecko/"

# The resource container. Its dex and its lib/ are inert on a JVM class path;
# atlas's AssetManager finds it by scanning for a zip holding an
# AndroidManifest.xml, and PackageParser reads that manifest as AAPT binary XML.
#
# So they are repackaged out, with the signature files: 47 MB of 113.5. What
# stays and looks like it should not is assets/omni.ja, the single biggest
# entry -- GeckoThread hands Gecko "-greomni <packageResourcePath>", so Gecko
# opens this very APK as its GRE jar and the unpacked gecko/ tree does not
# stand in. Without that entry the run is a SIGSEGV just after
# "GeckoThread: State changed to JNI_READY", with nothing logged.
#
# strip-apk.py keeps resources.arsc stored and word-aligned, which is the only
# form libandroidfw mmaps: unaligned it memcpy's all 17 MB and compressed it
# inflates them.
if [ -n "$FENIX_APK_STRIP" ]; then
	log "repackaging the resource APK, dropping $FENIX_APK_STRIP"
	python3 "$ROOT/scripts/strip-apk.py" --drop "$FENIX_APK_STRIP" \
		"$PAYLOAD_DIR/fenix.apk" "$INSTALL_DIR/fenix.apk" |
		while read -r l; do log "  $l"; done
else
	log "resource APK: shipped whole (FENIX_APK_STRIP empty)"
	cp "$PAYLOAD_DIR/fenix.apk" "$INSTALL_DIR/fenix.apk"
fi

install -m 0755 "$ROOT/run.sh" "$INSTALL_DIR/run.sh"
install -m 0644 "$ROOT/user.js" "$INSTALL_DIR/user.js"
cp "$ROOT/$HOOK.desktop" "$ROOT/$HOOK.apparmor" "$ROOT/$HOOK.svg" "$INSTALL_DIR/"

# clickable fills in @CLICK_ARCH@ and @CLICK_FRAMEWORK@; the version comes from
# the payload, so a click is identifiable as the Gecko build inside it.
app_version="$(sed -n 's/^version=//p' "$PAYLOAD_DIR/PAYLOAD.txt" 2>/dev/null | head -1)"
sed "s|@CLICK_VERSION@|${app_version:-0.0.0}|" "$ROOT/manifest.json" \
	>"$INSTALL_DIR/manifest.json"

# --- 6. the JVM -------------------------------------------------------------

if [ "$FENIX_VEHICLE" = image ]; then
	log "no JVM: this click is the ahead-of-time image alone"
else
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

	# The base CDS archive. A jlink image has none unless one is generated into it,
	# and the app archive run.sh writes on the device is a *dynamic* archive layered
	# on top of a base -- without one HotSpot refuses the flag outright and says so
	# only in its cds log, so every run has been paying full class loading with the
	# machinery in run.sh doing nothing. jlink's --generate-cds-archive cannot help
	# here: it runs the image's own java, and this is an aarch64 image built on
	# x86_64. qemu-user can run it, and a dump is about 8 s.
	#
	# It is not fatal if this fails. The click works without it, only slower, and a
	# build host with no qemu should still produce one.
	log "dumping the base CDS archive"
	jvm_java="$INSTALL_DIR/jvm/bin/java"
	if [ "$(uname -m)" = "aarch64" ]; then
		cds_run=("$jvm_java")
	elif command -v qemu-aarch64-static >/dev/null; then
		cds_run=(qemu-aarch64-static "$jvm_java")
	elif command -v qemu-aarch64 >/dev/null; then
		cds_run=(qemu-aarch64 "$jvm_java")
	else
		cds_run=()
		echo "  !! no qemu-aarch64 -- shipping without a base CDS archive" >&2
	fi
	if [ ${#cds_run[@]} -gt 0 ]; then
		# -Xshare:dump writes lib/server/classes.jsa, which is where the runtime
		# looks with no -XX:SharedArchiveFile, so run.sh needs no change.
		"${cds_run[@]}" -Xshare:dump >"$BUILD_DIR/cds-dump.log" 2>&1 ||
			echo "  !! -Xshare:dump failed, see $BUILD_DIR/cds-dump.log" >&2
	fi
	if [ -f "$INSTALL_DIR/jvm/lib/server/classes.jsa" ]; then
		log "  base CDS archive: $(du -h "$INSTALL_DIR/jvm/lib/server/classes.jsa" | cut -f1)"
	else
		echo "  !! no jvm/lib/server/classes.jsa -- AppCDS will be off on the device" >&2
	fi

	# The class-path archive (AppCDS) is NOT built here and NOT shipped: HotSpot
	# records each entry's size and mtime, so an archive made against this build
	# tree would be stale the moment the click is installed. run.sh creates one on
	# the device, in the cache directory, with -XX:+AutoCreateSharedArchive, on top
	# of the base archive above.
fi

# --- 7. bundle what the device does not have --------------------------------
# device-libs.txt is the device's own `ldconfig -p`. Anything the click needs
# that is not there travels with it. Closure, because a bundled library brings
# its own DT_NEEDED.

device_libs="$ROOT/device-libs.txt"
[ -f "$device_libs" ] || { echo "missing $device_libs" >&2; exit 1; }
search_dirs=("/usr/lib/$TRIPLE" "/lib/$TRIPLE" "$ATL/lib" "$ATL/lib/art")
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

# Nothing on this vehicle runs ART or the bionic shim, so if the closure reached
# for one of these the assumption behind the whole package has changed.
for unwanted in libart.so libnativebridge.so libc_bio.so.0 libdl_bio.so.0; do
	[ ! -e "$INSTALL_DIR/lib/$unwanted" ] ||
		{ echo "$unwanted was bundled -- something links it, which this vehicle does not expect" >&2; exit 1; }
done

# --- 8. strip and verify ----------------------------------------------------
# libxul alone is about 290 MB unstripped and about 150 MB stripped, which is
# most of the difference between a click that fits and one that does not.

if [ "${FENIX_SKIP_STRIP:-0}" != 1 ]; then
	log "stripping"
	find "$INSTALL_DIR/lib" "$INSTALL_DIR/gecko" -type f \
		\( -name '*.so' -o -name '*.so.*' \) \
		-exec "$TRIPLE-strip" --strip-unneeded {} + 2>/dev/null || true
	for l in android-translation-layer-hotspot android-translation-layer-image; do
		[ ! -f "$INSTALL_DIR/lib/$l" ] ||
			"$TRIPLE-strip" --strip-unneeded "$INSTALL_DIR/lib/$l" 2>/dev/null || true
	done
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
