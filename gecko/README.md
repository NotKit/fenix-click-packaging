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

That library is published as a release asset by the click build, which builds
atlas anyway (`atlas-libandroid-arm64.so`). Taking it from there rather than
rebuilding it is deliberate: the shim then measures the same atlas the click
ships, and the gap list cannot drift from it. The gap comes out at 283 entry
points; `ndk-gap.txt` is byte-identical between x86_64 and arm64.

**2. Gecko.**

    cd gecko-src
    . ./atl-glibc-env.sh
    export MOZCONFIG=$PWD/mozconfig-atl-glibc-arm64 ATL_SHIM_DIR=<this directory>
    ./mach build

**3. Stage it.** Writes `omni.ja` into the objdir (step 4 needs it) and the
payload's `gecko/` outside it:

    ./stage-gecko.sh --objdir gecko-src/obj-atl-glibc-arm64 --out build/gecko
    ./build-mozglue.sh --objdir gecko-src/obj-atl-glibc-arm64 --out build/mozglue/libmozglue.so

**4. Fenix.** Gradle, in the same tree, against the same objdir:

    JAVA_HOME=<a JDK 17> ANDROID_SDK_ROOT=<an SDK> \
      fenix/build-classpath.sh --src gecko-src --objdir gecko-src/obj-atl-glibc-arm64 \
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

`MEGAZORD_REF` pointing at Mozilla's published x86_64 build turns on the check
that matters — the uniffi symbol sets have to be equal, or the Kotlin
`Native.register` calls on the class path do not all bind.

## What is not built here

`fenix-jvm-sysroot-arm64.tar.zst` — `scripts/make-sysroot.sh` — needs an arm64
`art_standalone` build and a skia checkout. It changes rarely and is made by
hand; see the main README.
