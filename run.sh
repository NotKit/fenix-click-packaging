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
#   FENIX_VM=hotspot    start the bundled HotSpot instead of the GraalVM native
#                       image: 361 jars, class loading and an AppCDS archive.
#                       The image is the default when the click carries one.
#                       A click built for one vehicle only (FENIX_VEHICLE in
#                       build.sh) refuses the other with the reason.
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
#   FENIX_LOG=          where the log goes (default $CACHE/fenix.log). The
#                       previous run's is kept beside it as <log>.1.

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
# Probed with either launcher, because a click may carry only one of them.
PKG_ROOT="/opt/click.ubuntu.com/${PKG_NAME}/current"
[ -x "${PKG_ROOT}/lib/android-translation-layer-hotspot" ] ||
    [ -x "${PKG_ROOT}/lib/android-translation-layer-image" ] ||
    PKG_ROOT="${APP_DIR}"

# --- which vehicle ----------------------------------------------------------
# hotspot: the bundled JVM loads 361 jars at every start. image: atlas's
# android-translation-layer-image creates its VM from libfenix.so, which is the
# same jars compiled ahead of time -- so there is no class path, nothing to
# load and nothing for CDS to cache. The image only travels in a click built
# with one pinned (build.sh's FENIX_IMAGE_TAG).
#
# The image is the default wherever it is present. It matches warm HotSpot to
# the first frame and beats it to first paint, and unlike HotSpot it has no
# archive to lose: an upgrade renews every jar's mtime, which invalidates the
# AppCDS archive and costs about six seconds on the runs before a clean exit
# writes a new one. A click built with no image pinned has only the one
# vehicle and takes it silently.
if [ -z "${FENIX_VM:-}" ]; then
    if [ -e "${PKG_ROOT}/lib/android-translation-layer-image" ] &&
       [ -e "${PKG_ROOT}/lib/libfenix.so" ]; then
        FENIX_VM=image
    else
        FENIX_VM=hotspot
    fi
fi
case "${FENIX_VM}" in
    hotspot) NEED="lib/android-translation-layer-hotspot atlas/hax.jar classpath" ;;
    image)   NEED="lib/android-translation-layer-image lib/libfenix.so" ;;
    *) echo "fenix: FENIX_VM must be hotspot or image, not ${FENIX_VM}" >&2; exit 2 ;;
esac
for f in ${NEED}; do
    [ -e "${PKG_ROOT}/${f}" ] && continue
    echo "fenix: FENIX_VM=${FENIX_VM} but this click has no ${f}" >&2
    [ -f "${PKG_ROOT}/VEHICLE.txt" ] && cat "${PKG_ROOT}/VEHICLE.txt" >&2
    exit 2
done

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
# native object the click carries; gecko/ holds libxul and the NSS set. An
# image is dlopened by absolute path and carries its own runtime, so it needs
# neither jvm/lib/server nor $JAVA_HOME.
if [ "${FENIX_VM}" = image ]; then
    unset JAVA_HOME
    export LD_LIBRARY_PATH="${PKG_ROOT}/lib:${GECKO}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
else
    export LD_LIBRARY_PATH="${JAVA_HOME}/lib/server:${PKG_ROOT}/lib:${GECKO}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
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
# An image has no libjsig: Substrate installs its own SIGSEGV handler and
# nothing chains Gecko's behind it, so this is one of the things to watch when
# the image path is debugged.
JSIG="${PKG_ROOT}/jvm/lib/libjsig.so"
if [ "${FENIX_VM}" != image ] && [ -z "${FENIX_NO_JSIG:-}" ] && [ -e "${JSIG}" ]; then
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
[ "${FENIX_VM}" = image ] && FENIX_EXCLUDE=""
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
if [ "${FENIX_VM}" != image ] && [ "${FENIX_CDS:-auto}" != off ]; then
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
    # The archive is written on the way out of the VM, which is past the exec
    # below: nothing in this script runs again to record what it was written
    # against. So write the fingerprint now. A run that dies before producing an
    # archive does not fool the next one -- that check is "archive missing OR
    # fingerprint differs", and the missing archive alone forces a fresh write.
    [ -n "${CDSFP}" ] && printf '%s' "${CDSFP}" > "${JSA}.fp"
fi

JVMX=""
for o in ${FENIX_JVMOPTS:-}; do JVMX="${JVMX} -X ${o}"; done

# The redirect below truncates the log, and after the exec there is no parent
# left to tail it, so keep the previous run's output: after a crash it is the
# only place the reason is written down.
[ -f "${LOG}" ] && mv -f "${LOG}" "${LOG}.1"

echo "fenix: vm=${FENIX_VM} PKG_ROOT=${PKG_ROOT} state=${STATE} cache=${CACHE} log=${LOG} (previous run: ${LOG}.1)"

# Become the browser rather than supervise it. Lomiri addresses the app by the
# pid it started: the SIGSTOP when it is backgrounded, the SIGCONT, the SIGTERM
# on close and the "stopped" it reports all go there. A shell waiting on a child
# would take all of that itself and leave the JVM running behind it, which is
# why closing the app used to need a separate kill. So exec -- and nothing may
# be added after this line, it never runs.
#
# `env` execs the launcher in turn, so the pid still survives: it is here only
# to keep LD_PRELOAD off the shell helpers above, which cannot load libmozglue.
# The image ignores --api-impl-jar and -c with a warning -- it *is* the
# framework and the class path -- so those are simply not passed. The -XX:
# options are a different matter and must not be: on an image an unrecognised
# -XX: makes JNI_CreateJavaVM return JNI_ERR having printed nothing at all, and
# a second call in the same process hangs, so there is no degrading from it.
# shellcheck disable=SC2086
if [ "${FENIX_VM}" = image ]; then
    exec env LD_PRELOAD="${PRELOAD}" \
        "${PKG_ROOT}/lib/android-translation-layer-image" "${PKG_ROOT}/fenix.apk" \
        --vm-library "${PKG_ROOT}/lib/libfenix.so" \
        --framework-res "${PKG_ROOT}/atlas/framework-res.apk" \
        --natives-dir "${PKG_ROOT}/lib" \
        --library-path "${PKG_ROOT}/lib" \
        --library-path "${GECKO}" \
        -X "-Djna.boot.library.path=${PKG_ROOT}/lib" \
        -X "-Djna.library.path=${PKG_ROOT}/lib:${GECKO}" \
        -X "-Dport.shim.native.path=${PKG_ROOT}/lib/libportshim.so" \
        -X "-Djava.io.tmpdir=${TMPDIR}" \
        ${JVMX} \
        ${FENIX_URI:+-u "${FENIX_URI}"} \
        --sdk-int "${FENIX_SDK_INT:-28}" \
        "$@" > "${LOG}" 2>&1
fi

exec env LD_PRELOAD="${PRELOAD}" \
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
