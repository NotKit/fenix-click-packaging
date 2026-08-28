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
| `natives/megazord/` | `megazord/build-megazord.sh` — rarely; a release asset of its own |

## In order

Gecko is `NotKit/firefox` branch `atl/android-toolkit-glibc`, configured by that
tree's own `mozconfig-atl-glibc-arm64`. It reads `ATL_SHIM_DIR`, which is what
points it at this directory.

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
from it. The gap comes out at 283 entry points; `ndk-gap.txt` is byte-identical
between x86_64 and arm64.

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

`megazord/` is not part of a payload build. `libmegazord.so` tracks the
application-services revision the class path pins, which moves a few times a
year, so it is built on its own and published as a release asset that the
payload build downloads:

    APPSERVICES=<checkout> megazord/build-nss.sh          # ~40 min
    APPSERVICES=<checkout> megazord/build-megazord.sh     # ~3 min

`megazord.yml` runs these on an `ubuntu-24.04-arm` runner, where nothing is
cross: the triplet-prefixed compilers the scripts ask for are the host's own and
libz comes from apt. The same scripts cross-build on x86_64 with
`CC_CROSS=aarch64-linux-gnu-gcc-14` and an aarch64 `SYSLIBS`.

`MEGAZORD_REF` pointing at Mozilla's published x86_64 build turns on the check
that matters — the uniffi symbol sets have to be equal, or the Kotlin
`Native.register` calls on the class path do not all bind.

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

Two assets have to exist before the first payload build, because it downloads
rather than builds them:

* the `atl-sdk-arm64.tar.zst` of the SDK tag `build.sh` pins — published by
  atl-touch's own CI.
* `libmegazord-arm64.so` — published by `megazord.yml`, which is dispatch-only.

Both are found by scanning releases for the asset name, newest first, so no tag
has to be pinned.

A cold compile is about 70 minutes on a 4-core runner, which is what
`--disable-debug-symbols` buys — it is set only in CI, since the staged payload
has no debug sections anyway.

Two caches share the repository's 10 GB Actions budget: ccache and Gradle.
`~/.mozbuild` is deliberately not one of them. It is 7.5 GB before the SDK and
NDK zips CI leaves under `mozboot/`, so it does not fit, and a truncated entry
comes back as an NDK zip `unzip` refuses. Bootstrapping it fresh costs three
minutes, which is cheaper than the failure mode.
