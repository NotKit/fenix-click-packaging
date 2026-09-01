#!/bin/sh
# Device launcher: Fenix on the bundled OpenJDK 21 through atlas's HotSpot
# launcher, with Gecko (a glibc libxul) behind it.
#
# The package directory is READ-ONLY on Ubuntu Touch. Everything this run
# writes -- the AppCDS archive, the class-path symlink farm, the JVM's error
# file and perf data, and above all Firefox's profile -- goes under $STATE or
# $CACHE below, never beside the jars.
#
# Knobs (env, all optional):
#   FENIX_URI=          open this URL instead of the home screen. Nothing can
#                       type on Mir yet, so this is how a page is reached. A URL
#                       given as the first argument is used the same way.
#   FENIX_NO_GPU=1      ATL_NO_GPU=1, CPU raster -- the knob to flip first if
#                       it dies in skia.
#   FENIX_CDS=off       do not use or write the AppCDS archive (~2 s slower).
#   FENIX_E10S=1        let Gecko start content processes (default: single
#                       process, which is what user.js pins).
#   FENIX_RESET=1       move the profile aside before starting. The ONLY thing
#                       that discards browsing state; nothing does it silently.
#   FENIX_EXCLUDE=      space-separated substrings; a class-path jar whose name
#                       contains one is left off. Default: androidx.profileinstaller.
#   FENIX_JVMOPTS=      extra -X options, space separated.
#   FENIX_NO_JSIG=1     do not preload libjsig. The JVM then loses SIGSEGV to
#                       Gecko and JIT-compiled code dies on its first implicit
#                       null check; only for reproducing that.
#   FENIX_LOG=          where the log goes (default $CACHE/fenix.log).

APP_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_NAME=fenix.thekit
APP_HOOK=fenix

# The desktop file's Exec is "run.sh %u" and declares the http/https handlers,
# so Lomiri hands a URL over as the first argument. The launcher takes it as -u;
# a second positional would be a stray argument to it.
case "${1:-}" in
    http://*|https://*|about:*|file://*) FENIX_URI="${FENIX_URI:-$1}"; shift ;;
esac

# Prefer the version-independent 'current' path: it is stable across upgrades.
PKG_ROOT="/opt/click.ubuntu.com/${PKG_NAME}/current"
[ -x "${PKG_ROOT}/lib/android-translation-layer-hotspot" ] || PKG_ROOT="${APP_DIR}"

# --- writable state ---------------------------------------------------------
# STATE persists across upgrades and reboots and holds the profile; CACHE holds
# everything that can be regenerated. Both are outside the read-only package.
STATE="${XDG_DATA_HOME:-${HOME}/.local/share}/${PKG_NAME}"
CACHE="${XDG_CACHE_HOME:-${HOME}/.cache}/${PKG_NAME}"
mkdir -p "${STATE}" "${CACHE}"

# atlas appends "<apk basename>_" to this, so the app's own directory is
# ${STATE}/fenix.apk_ and Gecko's profile is
# ${STATE}/fenix.apk_/files/mozilla/*.default. It is NEVER removed here: the
# desktop and device *runners* wipe it every run to get a clean measurement,
# and that is exactly what must not happen to an installed browser.
export ANDROID_APP_DATA_DIR="${STATE}"
if [ -n "${FENIX_RESET:-}" ]; then
    stamp=$(date +%Y%m%d-%H%M%S)
    for d in "${STATE}"/*_; do
        [ -d "$d" ] && mv "$d" "${CACHE}/reset-${stamp}-$(basename "$d")"
    done
    echo "profile moved aside into ${CACHE}/reset-${stamp}-*"
fi

# HotSpot writes hsperfdata and its temporary files to java.io.tmpdir, and the
# JVM's own crash log to ErrorFile. Neither may land in the package.
export TMPDIR="${TMPDIR:-${CACHE}/tmp}"
mkdir -p "${TMPDIR}"

LOG="${FENIX_LOG:-${CACHE}/fenix.log}"

# --- display ----------------------------------------------------------------
# Lomiri starts a click app with XDG_RUNTIME_DIR=~/.cache and
# WAYLAND_DISPLAY=wayland-0, and the compositor's socket is in neither: it is in
# /run/user/<uid>. libwayland accepts an absolute WAYLAND_DISPLAY, so point it
# straight at the socket rather than moving XDG_RUNTIME_DIR, which the app uses
# for other things. Without this GLFW aborts before the first frame.
if [ ! -S "${XDG_RUNTIME_DIR:-}/${WAYLAND_DISPLAY:-wayland-0}" ]; then
    for _sock in "/run/user/$(id -u)/${WAYLAND_DISPLAY:-wayland-0}" "/run/user/$(id -u)/wayland-0"; do
        [ -S "${_sock}" ] && { WAYLAND_DISPLAY="${_sock}"; export WAYLAND_DISPLAY; break; }
    done
fi
export EGL_PLATFORM=wayland

# Without this the launcher opens its default window and Lomiri resizes it
# afterwards; the app then lays out for the full screen while the surface still
# holds the small buffer, and the right/bottom of the UI is cut off for good.
export ATL_FORCE_FULLSCREEN=1
# Lomiri never marks the app surface "maximized", so atlas's heuristic would
# report multi-window.
export ATL_MULTI_WINDOW=0
# dpi = 160 * GRID_UNIT_PX / 8. Unset means density 1.0 (dp == px), which makes
# a 1080-px phone lay out as a 1080-dp tablet.
export GRID_UNIT_PX="${GRID_UNIT_PX:-21}"

# The framework builds sans-serif and its weight aliases from these faces. It
# looks for them beside its own library, which is not where they are here; with
# no directory it asks fontconfig instead and gets Ubuntu, which has different
# metrics from the Roboto the layouts were written against.
[ -d "${PKG_ROOT}/atlas/system/fonts" ] && export ATL_FONT_DIR="${PKG_ROOT}/atlas/system/fonts"

# Wayland app_id must match the desktop file id (<pkg>_<app>_<version>) for
# Lomiri to associate the window with the launcher entry.
if [ -z "${APP_ID:-}" ] && [ -L "/opt/click.ubuntu.com/${PKG_NAME}/current" ]; then
    PKG_VERSION="$(basename "$(readlink -f "/opt/click.ubuntu.com/${PKG_NAME}/current")")"
    export APP_ID="${PKG_NAME}_${APP_HOOK}_${PKG_VERSION}"
fi

[ -n "${FENIX_NO_GPU:-}" ] && export ATL_NO_GPU=1

# --- the runtime ------------------------------------------------------------
export JAVA_HOME="${PKG_ROOT}/jvm"
GECKO="${PKG_ROOT}/gecko"
# libjvm.so is deliberately not in the launcher's RUNPATH. lib/ holds every
# native object the click carries; gecko/ holds libxul and the NSS set.
export LD_LIBRARY_PATH="${JAVA_HOME}/lib/server:${PKG_ROOT}/lib:${GECKO}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# mozglue's jemalloc has to own the process rather than be dlopened into one
# that already has glibc malloc, so it is preloaded -- but only into the
# launcher (see the env at the bottom), never into the shell helpers this script
# runs on the way there.
PRELOAD="${GECKO}/libmozglue.so${LD_PRELOAD:+:${LD_PRELOAD}}"
# Ubuntu Touch preloads libtls-padding.so so the Android GPU blob can use the
# bionic TLS slots (Mali keeps its per-thread context at tpidr_el0+24). That
# only works while the padding holds the first static-TLS offset, so it has to
# stay ahead of libmozglue, whose own TLS block would otherwise land there.
TLSPAD=/usr/lib/aarch64-linux-gnu/libtls-padding.so
[ -e "${TLSPAD}" ] && PRELOAD="${TLSPAD}:${PRELOAD}"

# HotSpot takes SIGSEGV for the implicit null checks, stack banging and
# safepoint polls it compiles into JIT code, so its handler has to stay
# installed. Gecko replaces it about two seconds into every run: SpiderMonkey's
# wasm trap handler takes SIGSEGV and SIGILL, nsSigHandlers takes SIGFPE,
# mozglue takes SIGBUS, and the profiler takes SIGUSR1/SIGUSR2 -- which is the
# "*** Handler was modified!" HotSpot prints in its own hs_err. libjsig is the
# JDK's answer: it keeps the VM's handlers primary and chains the app's behind
# them. Without it, staying alive means turning the JIT off, and -Xint is what
# makes this browser feel slow. FENIX_NO_JSIG=1 puts it back for a comparison.
JSIG="${JAVA_HOME}/lib/libjsig.so"
if [ -z "${FENIX_NO_JSIG:-}" ] && [ -e "${JSIG}" ]; then
    PRELOAD="${PRELOAD}:${JSIG}"
fi

# liblog drops anything below INFO without this, which is most of the app's own
# logging; on the device the journal is the only log there is.
export ANDROID_LOG_TAGS="${ANDROID_LOG_TAGS:-*:V}"

# --- Gecko ------------------------------------------------------------------
# Fonts come from atlas' libandroid, which implements the NDK system-font API
# over fontconfig; Gecko reads $ANDROID_ROOT/fonts only when that iterator
# yields nothing. Point it at the package's own Roboto so the fallback is the
# framework's faces rather than a crash -- gfxFT2FontList MOZ_CRASHes with "No
# font files found" on an empty directory. The trailing slash is load-bearing:
# Gecko appends "/fonts" to this string.
export ANDROID_ROOT="${PKG_ROOT}/atlas/system/"

export MOZ_ANDROID_LIBDIR_OVERRIDE="${GECKO}/libxul.so"
export MOZ_ANDROID_CPU_ABI=arm64-v8a
export MOZ_CRASHREPORTER_DISABLE=1
# nsProfileLock arms a fatal signal handler when it takes the profile lock and
# runs its _exit(signo) backstop after chaining; HotSpot's SIGSEGV handler
# returns normally (implicit null checks), so the first one after that would
# kill the process with status 11. Mandatory on this vehicle, unlike on ART.
export MOZ_DISABLE_SIG_HANDLER=1
[ -n "${FENIX_E10S:-}" ] || export MOZ_FORCE_DISABLE_E10S=1
export MOZ_ATL_ANW_EGLSURFACE=3
export ATL_NDK_STUB_SOFT=1

# GeckoRuntimeSettings pushes its own defaults after omni.ja, so a pref only
# sticks from user.js -- and the profile only exists from the second run on.
for p in "${STATE}"/*/files/mozilla/*.default; do
    [ -d "$p" ] && cp -f "${PKG_ROOT}/user.js" "$p/user.js"
done

# --- LeakCanary -------------------------------------------------------------
# This lane runs the debug variant (release runs R8, which the class-path build
# cannot use), and debug Fenix ships LeakCanary, which posts an *ongoing*
# "N retained objects" notification Lomiri shows and no tap dismisses. It only
# clears after a heap dump, and atlas has no android.os.Debug.dumpHprofData.
# LeakCanarySetup reads the switch from the app's default SharedPreferences.
PREFS="${STATE}/fenix.apk_/shared_prefs"
PREFSFILE="${PREFS}/${FENIX_PKG:-org.mozilla.fenix.debug}_preferences.xml"
if [ ! -s "${PREFSFILE}" ]; then
    mkdir -p "${PREFS}"
    {
        echo "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>"
        echo "<map>"
        echo '    <boolean name="pref_key_leakcanary" value="false" />'
        echo "</map>"
    } > "${PREFSFILE}"
fi

# --- the class path ---------------------------------------------------------
# A directory is passed as "dir/*"; JNI_CreateJavaVM does not expand that the
# way the `java` command does, so the launcher's append_class_path() does it.
# androidx.profileinstaller's startup Initializer asks the AssetManager for
# assets/dexopt/baseline.prof, which this APK does not have, and atlas hands
# openNonAsset's NULL straight to Asset_openFileDescriptor: SIGSEGV ~20 s in.
# Installing an ART baseline profile is meaningless on a JVM anyway.
: "${FENIX_EXCLUDE=androidx.profileinstaller}"
CPDIR="${PKG_ROOT}/classpath"
if [ -n "${FENIX_EXCLUDE}" ]; then
    # The farm is a symlink per jar and the package is read-only, so it is built
    # in the cache and rebuilt only when the jar set or the exclusions change.
    CPDIR="${CACHE}/classpath-active"
    want="$(printf '%s\n' "${FENIX_EXCLUDE}"; ls "${PKG_ROOT}/classpath" | md5sum)"
    if [ "$want" != "$(cat "${CPDIR}/.stamp" 2>/dev/null)" ]; then
        rm -rf "${CPDIR}"; mkdir -p "${CPDIR}"
        for j in "${PKG_ROOT}"/classpath/*.jar; do
            # shim.jar is passed on its own, ahead of everything, so that its
            # libcore classes win over anything an app jar shades in.
            case "${j##*/}" in shim.jar) continue ;; esac
            skip=
            for pat in ${FENIX_EXCLUDE}; do
                case "${j##*/}" in *"$pat"*) skip=1 ;; esac
            done
            [ -n "$skip" ] && continue
            ln -s "$j" "${CPDIR}/"
        done
        printf '%s' "$want" > "${CPDIR}/.stamp"
        echo "class-path farm rebuilt: $(ls "${CPDIR}"/*.jar | wc -l) jars"
    fi
fi

# --- AppCDS -----------------------------------------------------------------
# The archive holds the parsed, verified form of the ~14.9k classes this app
# loads and takes first frame from about 4.5 s to about 2.1 s. It is a cache,
# not a dependency, and it is written at VM *exit*, so it must live somewhere
# writable -- the package directory is not.
#
# -XX:+AutoCreateSharedArchive (JDK 19+) is self-healing: use it if valid, write
# a fresh one if missing or stale. Two things make that less automatic than it
# sounds, and both have bitten here:
#   * HotSpot records each class-path entry's size AND mtime, and a mismatch is
#     a warning to the cds log plus a silent fallback -- invisible from outside.
#     So the class path is fingerprinted the same way and a run that does not
#     match is treated as a creating run.
#   * the archive is written mode 444, so a stale one cannot be replaced in
#     place; it has to be removed first or every run warns and falls back for
#     ever.
CDSOPT=""
CDSFP=""
JSA="${CACHE}/app.jsa"
CDSLOG="${CACHE}/cds.log"
if [ "${FENIX_CDS:-auto}" != off ]; then
    CDSOPT="-X -XX:+AutoCreateSharedArchive -X -XX:SharedArchiveFile=${JSA}"
    CDSOPT="${CDSOPT} -X -Xlog:cds=warning:file=${CDSLOG}"
    rm -f "${CDSLOG}"
    CDSFP="$(ls -lLn --time-style=+%s "${CPDIR}"/*.jar "${PKG_ROOT}/atlas/hax.jar" \
        "${PKG_ROOT}/classpath/shim.jar" 2>/dev/null |
        awk '{print $5, $6, $NF}' | md5sum | cut -d" " -f1)"
    if [ ! -f "${JSA}" ] || [ "${CDSFP}" != "$(cat "${JSA}.fp" 2>/dev/null)" ]; then
        echo "CDS: archive missing or stale -- this run writes one"
        rm -f "${JSA}" "${JSA}.fp"
    fi
fi

JVMX=""
for o in ${FENIX_JVMOPTS:-}; do JVMX="${JVMX} -X ${o}"; done

echo "fenix: PKG_ROOT=${PKG_ROOT} state=${STATE} cache=${CACHE} log=${LOG}"

# shellcheck disable=SC2086
env LD_PRELOAD="${PRELOAD}" \
    "${PKG_ROOT}/lib/android-translation-layer-hotspot" "${PKG_ROOT}/fenix.apk" \
    --api-impl-jar "${PKG_ROOT}/atlas/hax.jar" \
    --framework-res "${PKG_ROOT}/atlas/framework-res.apk" \
    --natives-dir "${PKG_ROOT}/lib" \
    -c "${PKG_ROOT}/classpath/shim.jar" \
    -c "${CPDIR}/*" \
    --library-path "${PKG_ROOT}/lib" \
    --library-path "${GECKO}" \
    -X "-Djna.boot.library.path=${PKG_ROOT}/lib" \
    -X "-Djna.library.path=${PKG_ROOT}/lib:${GECKO}" \
    -X "-Dport.shim.native.path=${PKG_ROOT}/lib/libportshim.so" \
    -X "-Djava.io.tmpdir=${TMPDIR}" \
    -X "-XX:ErrorFile=${CACHE}/hs_err_%p.log" \
    ${JVMX} ${CDSOPT} \
    ${FENIX_URI:+-u "${FENIX_URI}"} \
    --sdk-int "${FENIX_SDK_INT:-28}" \
    "$@" > "${LOG}" 2>&1
rc=$?

# The journal is the only log Lomiri shows, and it would otherwise be empty:
# say enough there to know whether to go and read the file.
if [ "$rc" != 0 ]; then
    echo "fenix: exit ${rc}; last 40 lines of ${LOG}:" >&2
    tail -40 "${LOG}" >&2
fi

# The archive is written on the way out of the VM; record the fingerprint it was
# written against so the next run knows whether it still matches.
if [ -n "${CDSFP}" ] && [ -f "${JSA}" ]; then
    printf '%s' "${CDSFP}" > "${JSA}.fp"
fi
exit $rc
