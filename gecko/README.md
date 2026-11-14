# Building the payload

This directory builds `fenix-jvm-payload-arm64.tar.zst` — the larger of the two
release assets `build.sh` downloads, and the half that changes with every Gecko
or Fenix build. `scripts/make-payload.sh` packs what the scripts here produce.

Nothing in here runs on the device or inside the click container: this is a
cross build on an ordinary x86_64 machine, and `.github/workflows/payload.yml`
runs exactly the sequence below.

## The five inputs

| | from |
| --- | --- |
| `gecko/` | `stage-gecko.sh` — the objdir's `dist/bin`, debug sections removed, plus the two shim libraries |
| `gecko/libmozglue.so` | `build-mozglue.sh` — relinked out of the same objdir |
| `classpath/` | `fenix/build-classpath.sh` — ~360 jars |
| `fenix.apk` | `fenix/stage-apk.sh` — the Gradle APK with the objdir's `omni.ja` put in |
| `natives/megazord/` | the same Gecko objdir's `dist/bin/libmegazord.so` |

## In order

Gecko is `NotKit/firefox` branch `atl/android-toolkit-glibc`, configured by that
tree's own `mozconfig-atl-glibc-arm64`. It reads `ATL_SHIM_DIR`, which is what
points it at this directory. The current port is based on
`FIREFOX-ANDROID_160_0_RELEASE`.

    git clone -b atl/android-toolkit-glibc https://github.com/NotKit/firefox gecko-src

**1. The link shim.** The header shim is committed complete; the link shim's
outputs are per-architecture and are generated, because they name the
translation layer's own `libandroid.so.0`:

    curl -Lo libandroid.so.0 <the arm64 libandroid.so.0 of the atlas build>
    cd android-libs-shim
    OUTDIR=../android-libs-shim-arm64 \
      ATL_LIBANDROID=$PWD/../libandroid.so.0 \
      CC="$HOME/.mozbuild/clang/bin/clang --target=aarch64-linux-gnu -fuse-ld=lld" \
      SYSROOT=$HOME/.mozbuild/sysroot-aarch64-linux-gnu \
      ./regenerate.sh

That library comes out of the same SDK tarball the click is assembled from —
`usr/lib/libandroid.so.0` of the `sdk-<sha>` release `build.sh` pins — so the
shim measures exactly the atlas the click ships and the gap list cannot drift
from it. The current SDK leaves 266 stubbed entry points.

**2. Gecko.** `rustup target add aarch64-unknown-linux-gnu` first, if the
toolchain has no std for it -- configure fails at "checking for rust target
triplet" without one.

    cd gecko-src
    . ./atl-glibc-env.sh
    export MOZCONFIG=$PWD/mozconfig-atl-glibc-arm64 ATL_SHIM_DIR=<this directory>
    ./mach build

`mach build` ends by failing in `android-stage-package`:

    error: mobile/android/installer/package-manifest.in:66: Missing file(s): bin/libmozglue.so

That is expected and not fatal here. `MOZ_FOLD_LIBS` is empty in this
configuration, so `dist/bin` has no `libmozglue.so` -- step 3 relinks it -- and
`package-manifest.in` also wants the crash reporter and clearkey libraries this
build does not produce. Everything the payload needs is built before the
packager runs; CI checks for those outputs rather than for a zero exit code.

**3. Stage it.** Writes `omni.ja` into the objdir (step 4 needs it) and the
payload's `gecko/` outside it:

    ./stage-gecko.sh --objdir gecko-src/obj-atl-glibc-arm64 --out build/gecko
    ./build-mozglue.sh --objdir gecko-src/obj-atl-glibc-arm64 --out build/mozglue/libmozglue.so
    mkdir -p build/megazord
    "$HOME/.mozbuild/clang/bin/llvm-objcopy" --strip-debug \
        gecko-src/obj-atl-glibc-arm64/dist/bin/libmegazord.so build/megazord/libmegazord.so

**4. Fenix.** Gradle, in the same tree. `settings.gradle` finds the objdir by
running `./mach environment`, which is why this takes the mozconfig and not a
path:

    JAVA_HOME=<a JDK 17> ANDROID_SDK_ROOT=<an SDK> \
      fenix/build-classpath.sh --src gecko-src \
                               --mozconfig gecko-src/mozconfig-atl-glibc-arm64 \
                               --out build/fenix
    fenix/stage-apk.sh --apk-dir build/fenix/apk \
                       --omni gecko-src/obj-atl-glibc-arm64/dist/bin/assets/omni.ja \
                       --out build/fenix/fenix-jvm.apk

**5. Pack.**

    ../scripts/make-payload.sh \
        --gecko     build/gecko \
        --mozglue   build/mozglue/libmozglue.so \
        --classpath build/fenix/classpath \
        --apk       build/fenix/fenix-jvm.apk \
        --megazord  build/megazord/libmegazord.so

## The megazord

Firefox 160 includes application-services in its source tree. The port's
mozconfigs enable `--enable-appservices-in-tree` and set `MEGAZORD_VERSION`
from `mobile/android/version.txt`. Gecko builds `libmegazord.so` against its
own NSS libraries, and Gradle builds the matching JVM bindings from that same
tree. The payload uses this library, so its native API and version match the
class path.

`megazord/` and `megazord.yml` remain available for rebuilding older payloads.

## What is not built here

atlas and its native chain. That is `atl-sdk-arm64.tar.zst`, built by
atl-touch's own CI (`ci/build-sdk.sh`) on a native arm64 runner and pinned by
`build.sh`; this directory only borrows its `libandroid.so.0` for the link
shim.

## In CI

`.github/workflows/payload.yml` is the sequence above, on `ubuntu-24.04`.
It is `workflow_dispatch` (with the Gecko ref as an input) plus a
`repository_dispatch` of type `gecko-push`, so a push to the Gecko branch can
start a build with no commit here. To wire that up, a workflow in the Gecko fork
needs a token that can dispatch into this repository:

    - run: gh api repos/NotKit/fenix-click-packaging/dispatches \
             -f event_type=gecko-push -F client_payload[ref]="$GITHUB_REF_NAME"
      env: { GH_TOKEN: "${{ secrets.PACKAGING_DISPATCH_TOKEN }}" }

The `atl-sdk-arm64.tar.zst` of the SDK tag pinned by `build.sh` must already
exist, published by atl-touch's CI. The payload builds its own megazord.

A cold compile is about 70 minutes on a 4-core runner, which is what
`--disable-debug-symbols` buys — it is set only in CI, since the staged payload
has no debug sections anyway.

Two caches share the repository's 10 GB Actions budget: ccache and Gradle.
`~/.mozbuild` is deliberately not one of them. It is 7.5 GB before the SDK and
NDK zips CI leaves under `mozboot/`, so it does not fit, and a truncated entry
comes back as an NDK zip `unzip` refuses. Bootstrapping it fresh costs three
minutes, which is cheaper than the failure mode.
