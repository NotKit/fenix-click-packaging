#!/bin/bash
# Compile Fenix (with android-components and geckoview) from the Gecko tree and
# assemble a JVM class path -- ~360 ordinary jars -- plus the APKs of the same
# build.
#
#   ./build-classpath.sh --src DIR --mozconfig FILE [--out DIR] [--variant debug]
#
# Drives the :fenix:jarForJvm task added by jvm.gradle, which the tree's
# build.gradle applies only under -PfenixJvm.
#
#   --src        the Gecko checkout (mobile/android/fenix lives in it)
#   --mozconfig  the mozconfig that tree was configured with.  settings.gradle
#               resolves the objdir by running `./mach environment`, which reads
#               MOZCONFIG; geckoview's jniLibs and assets srcDirs point into it.
#   --out        classpath/ and apk/ are written here
#
# JAVA_HOME must be a JDK 17: that is what the tree's Gradle runs on, and the
# class files it emits target 17 (android-components jvmTargetCompatibility),
# which HotSpot 21 loads.  ANDROID_SDK_ROOT must be an SDK with the platform
# and build-tools the tree pins -- `./mach bootstrap` installs both.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

SRC=""
MOZCONFIG_FILE="${MOZCONFIG:-}"
OUT="$ROOT/build/fenix"
VARIANT="debug"
TASK=":fenix:jarForJvm"
EXTRA=()

while [ $# -gt 0 ]; do
	case "$1" in
	--src)       SRC="$2"; shift ;;
	--mozconfig) MOZCONFIG_FILE="$2"; shift ;;
	--out)     OUT="$2"; shift ;;
	--variant) VARIANT="$2"; shift ;;
	--no-apk)  TASK=":fenix:classesForJvm" ;;
	*)         EXTRA+=("$1") ;;
	esac
	shift
done

[ -n "$SRC" ] || { echo "missing --src" >&2; exit 2; }
[ -n "$MOZCONFIG_FILE" ] || { echo "missing --mozconfig" >&2; exit 2; }
[ -f "$MOZCONFIG_FILE" ] || { echo "no $MOZCONFIG_FILE" >&2; exit 1; }
[ -x "$SRC/gradlew" ] || { echo "no $SRC/gradlew" >&2; exit 1; }
[ -n "${JAVA_HOME:-}" ] || { echo "set JAVA_HOME to a JDK 17" >&2; exit 1; }
[ -n "${ANDROID_SDK_ROOT:-}" ] || { echo "set ANDROID_SDK_ROOT" >&2; exit 1; }
export ANDROID_HOME="$ANDROID_SDK_ROOT"

export FENIX_JVM_OUT="$OUT"
CLASSPATH_DIR="$OUT/classpath"
mkdir -p "$CLASSPATH_DIR"

# machStagePackage/machBuildFaster re-enter the moz.build system to restage
# dist/.  This objdir has MOZ_FOLD_LIBS empty, so dist/bin has no libmozglue.so
# and machStagePackage's own doFirst check fails on exactly that.
# GRADLE_INVOKED_WITHIN_MACH_BUILD=1 is the tree's own switch for "the binaries
# are already staged, don't rebuild them" (MachExec.kt geckoBinariesOnlyIf).
# The APK therefore ships no omni.ja and no Gecko .so; stage-apk.sh puts the
# objdir's omni.ja in afterwards.
export GRADLE_INVOKED_WITHIN_MACH_BUILD=1
export MOZCONFIG="$MOZCONFIG_FILE"

# --no-configure-on-demand: the tree sets org.gradle.configureondemand=true,
# which configures :fenix lazily *after* gradle.projectsEvaluated has fired, so
# jvm.gradle's task names would not exist when they are looked up.
cd "$SRC"
GRADLE_OPTS="-Dfile.encoding=utf-8" \
JAVA_TOOL_OPTIONS="-Dfile.encoding=utf-8" \
./gradlew --console=plain \
	--no-configure-on-demand \
	-PfenixJvm \
	"-PfenixJvmInclude=$HERE/jvm.gradle" \
	"-PfenixJvmVariant=$VARIANT" \
	"$TASK" ${EXTRA[0]+"${EXTRA[@]}"}

jars=$(find "$CLASSPATH_DIR" -maxdepth 1 -name '*.jar' | wc -l)
[ -s "$CLASSPATH_DIR/fenix-app.jar" ] || { echo "missing fenix-app.jar" >&2; exit 1; }
[ -s "$CLASSPATH_DIR/fenix-res.jar" ] || { echo "missing fenix-res.jar" >&2; exit 1; }
[ "$jars" -ge 100 ] || { echo "only $jars jars in $CLASSPATH_DIR" >&2; exit 1; }
echo "class path: $jars jars in $CLASSPATH_DIR"
ls "$OUT/apk" 2>/dev/null || true
