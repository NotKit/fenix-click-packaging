#!/bin/bash
# Build a GraalVM native-image shared library of Fenix: the same framework, shim
# and class path the HotSpot click puts on its class path, compiled ahead of
# time and exporting the JNI Invocation API so atlas's
# android-translation-layer-image can create its VM from it.
#
#   ./image/build-image.sh --stub    a one-class image, proving the toolchain
#                                    on this machine without any of Fenix
#   ./image/build-image.sh           the real thing
#
# native-image cannot cross-compile: the image is always for the machine the
# builder runs on, and every input here (the jars, the shim, the traced JSON) is
# architecture-neutral. So an aarch64 image is this script on an aarch64 machine
# with ~16 GB and a C toolchain -- which is what .github/workflows/image.yml
# rents from GitHub's arm64 runners. Do not try to fake it: qemu-user runs the
# builder 38x slower and Houdini does not finish at all (firefox-atl
# jvm-run/image/NOTES.md has the numbers).
#
# Inputs, all overridable:
#   GRAALVM_HOME   a GraalVM CE 21 for *this* architecture
#   HAX            atlas's api-impl_classes.jar, out of the SDK tarball
#   SHIMJAR        shim.jar, built by shim/build.sh
#   APPCP          a directory of Fenix's jars, out of the payload tarball
#   IMG_CONFIG     the traced metadata, default image/ni-config
#   OUTDIR         where libfenix.so lands
#   IMG_XMX        builder heap, default 10g
#   IMG_PARALLELISM  builder threads, default nproc
#   IMG_XUL        the payload's libxul.so, default $APPCP/../gecko/libxul.so
#   IMG_EXTRA      extra native-image arguments
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GRAALVM_HOME:?set GRAALVM_HOME to a GraalVM CE 21 for this architecture}"
: "${HAX:?set HAX to the SDK's usr/lib/java/api-impl_classes.jar}"
: "${SHIMJAR:?set SHIMJAR to the shim jar shim/build.sh produced}"
: "${APPCP:?set APPCP to the payload's classpath directory}"
: "${IMG_CONFIG:=$HERE/ni-config}"
: "${OUTDIR:=$PWD/build/image}"

NI="$GRAALVM_HOME/bin/native-image"
[ -x "$NI" ] || { echo "no native-image at $NI" >&2; exit 1; }
want="$(uname -m)"
have="$(file -b "$GRAALVM_HOME/lib/server/libjvm.so" | grep -oE 'x86-64|aarch64' | head -1)"
[ "$have" = x86-64 ] && have=x86_64
[ "$have" = "$want" ] ||
	{ echo "GRAALVM_HOME is a $have build, this machine is $want" >&2; exit 1; }
mkdir -p "$OUTDIR"

# The launcher dlopens the .so and looks these three up by name (vm_image.c), so
# an image missing one is useless however well it built. --no-fallback is what
# makes the check meaningful: a fallback image exports them and still needs a JVM.
assert_invocation_api() {
	local so="$1" exports
	[ -f "$so" ] || { echo "native-image produced no $so" >&2; exit 1; }
	exports=$(nm -D --defined-only "$so")
	for sym in JNI_CreateJavaVM JNI_GetCreatedJavaVMs JNI_GetDefaultJavaVMInitArgs; do
		grep -qE " T $sym\$" <<<"$exports" || { echo "$so does not export $sym" >&2; exit 1; }
	done
}

# native-image forks a builder JVM, so the pid we start is never the interesting
# one; poll the tree. Wall clock and peak RSS are reported numbers here, because
# whether a runner can host this build at all is decided by them.
tree_rss_kb() {
	local pids=("$1") next=() total=0 kb children
	while [ "${#pids[@]}" -gt 0 ]; do
		next=()
		for p in "${pids[@]}"; do
			kb=$(ps -o rss= -p "$p" 2>/dev/null || true)
			[ -z "$kb" ] || total=$((total + kb))
			mapfile -t children < <(pgrep -P "$p" 2>/dev/null || true)
			next+=(${children[@]+"${children[@]}"})
		done
		pids=(${next[@]+"${next[@]}"})
	done
	echo "$total"
}

run_ni() {
	local log="$1"; shift
	printf '%q\n' "$@" >"${log%.log}-argv.txt"
	local started peak=0 now status=0
	started=$(date +%s)
	"$@" >"$log" 2>&1 &
	local pid=$!
	while kill -0 "$pid" 2>/dev/null; do
		now=$(tree_rss_kb "$pid"); [ "$now" -le "$peak" ] || peak="$now"
		sleep 2
	done
	wait "$pid" || status=$?
	printf 'elapsed_s=%s\npeak_rss_kb=%s\nstatus=%s\n' \
		"$(( $(date +%s) - started ))" "$peak" "$status" | tee "${log%.log}-stats.env"
	return "$status"
}

if [ "${1:-}" = --stub ]; then
	d="$OUTDIR/stub"; mkdir -p "$d/classes"
	cat >"$d/VmCheck.java" <<'EOF'
public class VmCheck {
	public static void main(String[] a) {
		System.out.println("vm-check: image alive, java.vm.name=" + System.getProperty("java.vm.name"));
	}
}
EOF
	"$GRAALVM_HOME/bin/javac" -d "$d/classes" "$d/VmCheck.java"
	cat >"$d/jni-config.json" <<'EOF'
[
  { "name": "VmCheck", "methods": [{ "name": "main", "parameterTypes": ["java.lang.String[]"] }] },
  { "name": "java.lang.System", "methods": [{ "name": "getProperty", "parameterTypes": ["java.lang.String"] }] },
  { "name": "java.lang.String" }
]
EOF
	run_ni "$d/build.log" "$NI" --shared -o "$d/libatl-vm-stub" -cp "$d/classes" \
		-H:JNIConfigurationFiles="$d/jni-config.json" --no-fallback \
		--add-opens=java.base/java.io=ALL-UNNAMED
	assert_invocation_api "$d/libatl-vm-stub.so"
	echo "stub ok: $d/libatl-vm-stub.so ($(stat -c%s "$d/libatl-vm-stub.so") bytes)"
	exit 0
fi

# --- the real image ---------------------------------------------------------
# Two config directories: ni-config/ is the agent's trace of a full desktop boot
# and is never edited, extra-config/ is what image runs proved the trace could
# not see. See extra-config/README.md for why each entry is there.

for f in "$HAX" "$SHIMJAR"; do
	[ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done
for f in jni-config.json reflect-config.json proxy-config.json resource-config.json \
	serialization-config.json; do
	[ -f "$IMG_CONFIG/$f" ] || { echo "no $IMG_CONFIG/$f" >&2; exit 1; }
done

# The class path in the launcher's order: framework, shim, then the app jars.
# Order decides duplicate classes and the framework has to win. The jars are
# listed one by one: neither JNI_CreateJavaVM nor native-image expands "dir/*",
# and a literal "*" entry contributes nothing -- silently, with the whole app
# missing from the image.
mapfile -t JARS < <(find "$APPCP" -maxdepth 1 -name '*.jar' | sort)
[ "${#JARS[@]}" -ge 100 ] || { echo "only ${#JARS[@]} jars in $APPCP" >&2; exit 1; }

# run.sh drops these jars from the HotSpot class path at run time; an image has
# no class path to drop them from, so they have to go here or not at all.
# androidx.profileinstaller's startup Initializer asks the AssetManager for
# assets/dexopt/baseline.prof, which this APK does not have, and atlas hands
# openNonAsset's NULL straight to Asset_openFileDescriptor: SIGSEGV. An ART
# baseline profile is meaningless on this runtime anyway. Keep this in step with
# run.sh's FENIX_EXCLUDE.
: "${IMG_EXCLUDE:=androidx.profileinstaller}"
if [ -n "$IMG_EXCLUDE" ]; then
	kept=()
	for j in "${JARS[@]}"; do
		skip=""
		for pat in $IMG_EXCLUDE; do
			case "${j##*/}" in *"$pat"*) skip=1 ;; esac
		done
		[ -n "$skip" ] && { echo "excluded from the image: ${j##*/}"; continue; }
		kept+=("$j")
	done
	JARS=("${kept[@]}")
fi

# gapclasses/: android.* types atlas lacked that a closed world has to resolve
# anyway. Both are in atlas as of 8815f1d7, so an SDK new enough to carry them
# makes this directory dead weight -- and a stub shadowing a real class would be
# worse than dead. Compiled only for the ones the framework really is missing.
GAP=""
missing=()
while read -r src; do
	cls="${src#"$HERE/gapclasses/"}"; cls="${cls%.java}.class"
	unzip -l "$HAX" "$cls" >/dev/null 2>&1 || missing+=("$src")
done < <(find "$HERE/gapclasses" -name '*.java')
if [ "${#missing[@]}" -gt 0 ]; then
	GAP="$OUTDIR/gapclasses"
	rm -rf "$GAP"; mkdir -p "$GAP"
	"$GRAALVM_HOME/bin/javac" -nowarn -d "$GAP" "${missing[@]}"
	echo "gapclasses: ${#missing[@]} classes this framework is missing"
	printf '  %s\n' "${missing[@]#"$HERE/gapclasses/"}"
else
	echo "gapclasses: none needed, the framework has them all"
fi
# The builder Feature that installs atlas's JCE provider into the *builder's*
# provider list. It has to be on the image class path for --features to find it,
# and it compiles against the builder's own org.graalvm.nativeimage API.
FEATDIR="$OUTDIR/feature"
rm -rf "$FEATDIR"; mkdir -p "$FEATDIR"
"$GRAALVM_HOME/bin/javac" -nowarn -d "$FEATDIR" \
	-cp "$GRAALVM_HOME/lib/svm/builder/svm.jar:$HAX" \
	"$HERE/feature/fenixni/KeyStoreProviderFeature.java"

CP="$HAX:$SHIMJAR:$(IFS=:; echo "${JARS[*]}")${GAP:+:$GAP}:$FEATDIR"
echo "image class path: framework + shim + ${#JARS[@]} jars"

# The classes Android instantiates by *name* -- every View the layout inflater
# builds and every Fragment the navigation graph names -- are invisible to the
# trace and to the analysis alike. gen-reflect-config.py reads the class
# hierarchy out of the jars and registers every descendant of View and Fragment;
# see its docstring. Generated rather than committed, because a payload bump
# moves the set and a stale list is wrong exactly where it matters.
GENCFG="$OUTDIR/generated-reflect-config.json"
GENJNI="$OUTDIR/generated-jni-config.json"
XUL="${IMG_XUL:-$APPCP/../gecko/libxul.so}"
[ -f "$XUL" ] || { echo "no libxul.so at $XUL; set IMG_XUL" >&2; exit 1; }
python3 "$HERE/gen-reflect-config.py" "$GENCFG" "$GENJNI" "$XUL" "$HAX" "$SHIMJAR" "${JARS[@]}"

# SDK_INT is a static final int: initialised at build time it is constant-folded
# into every "SDK_INT >= N" branch in the app and no run-time -D can undo it.
INIT_RT="android.os.Build\$VERSION,android.os.SystemProperties"
[ -z "${IMG_INIT_AT_RUNTIME:-}" ] || INIT_RT="$INIT_RT,$IMG_INIT_AT_RUNTIME"

# native-image's default policy is run-time initialisation for everything it has
# not proven safe, and it *fails the build* when a class it expected at run time
# was initialised during the build anyway. Each name in the file answers one such
# error from a previous build; it is a file rather than a list in this script so
# the set is reviewable as a diff. Nothing under android.*, org.mozilla.* or
# mozilla.* belongs in it without reading the class first -- those are the ones
# whose <clinit> can read a -D property the build host cannot answer.
BT_FILE="${IMG_BUILDTIME_FILE:-$HERE/initialize-at-build-time.txt}"
INIT_BT=""
[ ! -f "$BT_FILE" ] || INIT_BT=$(grep -vE '^\s*(#|$)' "$BT_FILE" | paste -sd, -)
[ -z "${IMG_INIT_AT_BUILDTIME:-}" ] || INIT_BT="${INIT_BT:+$INIT_BT,}$IMG_INIT_AT_BUILDTIME"
BT_OPTS=()
[ -z "$INIT_BT" ] || BT_OPTS=("--initialize-at-build-time=$INIT_BT")

# JCE providers have to be known at build time: JceSecurity's verification map is
# built then, and a provider added by Security.addProvider() at run time gets
# "Trying to verify a provider that was not registered at build time". atlas's
# AndroidKeyStore provider is a named class as of 86480a1d; before that it was an
# anonymous subclass built in Context.java, which Substrate cannot instantiate,
# so on an older framework this argument is accepted and does not work.
SECPROV="${IMG_SECURITY_PROVIDERS:-}"
if [ -z "$SECPROV" ]; then
	if unzip -l "$HAX" 'android/security/keystore/AndroidKeyStoreProvider.class' >/dev/null 2>&1; then
		SECPROV="android.security.keystore.AndroidKeyStoreProvider"
	else
		SECPROV="android.content.Context\$1"
		echo "!! this framework predates atlas 86480a1d: the keystore provider is" >&2
		echo "!! anonymous and the image will fail on KeyGenerator.getInstance" >&2
	fi
fi
echo "security provider: $SECPROV"

EXTRA=()
read -ra EXTRA -d '' <<<"${IMG_EXTRA:-}" || true

run_ni "$OUTDIR/build.log" \
	"$NI" \
	--shared -o "$OUTDIR/libfenix" \
	-cp "$CP" \
	-H:ConfigurationFileDirectories="$IMG_CONFIG,$HERE/extra-config" \
	-H:ReflectionConfigurationFiles="$GENCFG" \
	-H:JNIConfigurationFiles="$GENJNI" \
	--features=fenixni.KeyStoreProviderFeature \
	--no-fallback \
	--add-opens=java.base/java.io=ALL-UNNAMED \
	-H:+UnlockExperimentalVMOptions \
	-H:+ReportExceptionStackTraces \
	-H:+PrintClassInitialization \
	-H:+WarnAboutMissingReflectionOrJNIMetadataElements \
	"-J-Xmx${IMG_XMX:-10g}" \
	"--parallelism=${IMG_PARALLELISM:-$(nproc)}" \
	"--initialize-at-run-time=$INIT_RT" \
	"-H:AdditionalSecurityProviders=$SECPROV" \
	${BT_OPTS[@]+"${BT_OPTS[@]}"} \
	${EXTRA[@]+"${EXTRA[@]}"}

assert_invocation_api "$OUTDIR/libfenix.so"
echo "image ok: $OUTDIR/libfenix.so ($(stat -c%s "$OUTDIR/libfenix.so") bytes)"
