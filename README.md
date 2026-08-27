# fenix-click-packaging

An Ubuntu Touch click of **Firefox for Android (Fenix) running on a stock
OpenJDK**, on top of the Android Translation Layer (atlas) and a Gecko compiled
natively for glibc.

There is no ART and no dex in this package. Fenix's Java arrives as ~360
ordinary jars on a JVM class path, the framework arrives as `hax.jar` (javac
output, not a dex), and `libxul.so` is an aarch64 glibc shared library that
`android-translation-layer-hotspot` loads into the same process as the JVM. That
is the whole reason this builds in minutes on an ordinary x86_64 machine:
`art_standalone` is the only piece of the ATL stack that cannot be
cross-compiled, and this vehicle does not contain it.

Siblings, for orientation:

| repository | what it packages |
| --- | --- |
| **mercurygram-click-packaging** | Telegram on ART + `bionic_translation` + dex — a native arm64 build under qemu |
| **mercurygram-src** `linux-port/click/` | the same app on OpenJDK — the cross build this one is modelled on |
| **firefox-atl** | where Gecko, the class path, the shim and the runners are developed |

## Layout of the installed click

    lib/            every native object, flat: the HotSpot launcher, atlas's
                    natives, libskia, libportshim, libjnidispatch, libmegazord,
                    the art support libraries and each library Ubuntu Touch does
                    not ship. One directory, so the natives' $ORIGIN/ RUNPATH
                    resolves all of it on the device.
    gecko/          libxul.so, the NSS set, libmozglue.so and dist/bin's data
                    (chrome/, components/, modules/, ...). libmozglue stays in
                    here on purpose — GeckoLoader putenvs MOZ_ANDROID_LIBDIR
                    from wherever it found it and APKOpen dlopens libnss3,
                    libnspr4, libplc4 and libmozsqlite3 out of that directory.
    atlas/          hax.jar, framework-res.apk and the Roboto faces the
                    framework builds its generic families from
    classpath/      shim.jar and Fenix's jars
    jvm/            a jlink image of the arm64 OpenJDK 21, not a copy of the JDK
    fenix.apk       resources, assets and the binary manifest — its dex and its
                    lib/ are inert on a JVM class path, but atlas's
                    AssetManager finds resource containers by scanning the class
                    path for zips holding an AndroidManifest.xml
    run.sh          the device launcher
    user.js         the Gecko prefs the profile is seeded with

The profile lives in `~/.local/share/fenix.thekit` and nothing removes it;
`FENIX_RESET=1` moves it aside. Everything regenerable — the AppCDS archive, the
class-path symlink farm, `$ANDROID_ROOT/fonts` and the log — is in
`~/.cache/fenix.thekit`.

## The two tarballs

Two inputs cannot be built inside a click container, and both are consumed as
release assets of this repository, pinned by tag in `build.sh`
(`FENIX_SYSROOT_TAG`, `FENIX_PAYLOAD_TAG`) and verified against
`FENIX_SYSROOT_SHA256` / `FENIX_PAYLOAD_SHA256` when those are set.

**`fenix-jvm-sysroot-arm64.tar.zst`** (27 MB) — the build-time sysroot:
`art_standalone`'s `libandroidfw` and friends plus their headers, ART's boot
jars (javac compiles atlas's framework against libcore, not against the JDK),
GLFW 3.4, and a prebuilt `libskia.so` with skia's `include/` and `modules/`.
None of it can be cross-built; all of it changes rarely.

    scripts/make-sysroot.sh --from-art-click <ART packaging arm64 build dir> \
                            --skia-src   <the skia checkout its atlas used>

**`fenix-jvm-payload-arm64.tar.zst`** (205 MB) — Gecko for aarch64, Fenix's
class path, the resource APK and the aarch64 megazord. This is the half that
changes with every Gecko or Fenix build. Gecko itself is built from
[NotKit/firefox](https://github.com/NotKit/firefox) branch
`atl/android-toolkit-glibc`; the staging of all five inputs is driven from the
**firefox-atl** tree, which documents each one:

    scripts/make-payload.sh \
        --gecko     <firefox-atl payload-arm64/gecko> \
        --classpath <jvm-run/fenixbuild output: the ~360 jars> \
        --apk       <jvm-run/fenixbuild/stage-apk.sh output> \
        --mozglue   <firefox-atl payload-arm64/mozglue/libmozglue.so> \
        --megazord  <jvm-run/arm64/build-megazord-arm64.sh output>

Upload each with `gh release create <tag> dist/<file> dist/<file>.sha256`, then
point `build.sh`'s default tag at it.

For local iteration neither has to be published: `FENIX_SYSROOT_DIR` and
`FENIX_PAYLOAD_DIR` name unpacked trees and are used as-is.

## Building

    git submodule update --init --remote
    clickable build --arch arm64 --skip-review
    clickable install --ssh <device>

`--remote` because `atl-touch` is pinned to a *branch* in `.gitmodules`, not just
to the recorded commit: this packaging follows its tip rather than trailing it,
and CI does the same before every build. Leave `--remote` off, or set the
`workflow_dispatch` input to false, to reproduce an older build exactly.

`--skip-review` because the package fails two `click-review` checks by design,
both shared with the sibling packagings:

* `security:template_valid: 'unconfined' not allowed` — a JVM plus a browser
  engine needs far more than the click templates grant. This blocks an OpenStore
  submission, not a local install.
* `lint:hardcoded_paths: '/opt/click.ubuntu.com/' in run.sh` — deliberate: the
  launcher prefers the version-independent `current` symlink and falls back to
  its own directory.

`device-libs.txt` is the device's own `ldconfig -p`. `build.sh` bundles every
`DT_NEEDED` that is not in it, transitively, and **fails** if something is
neither on the device nor in the container — which is what stops "it linked in
the container" from becoming a silent load failure on the phone.

## Knobs at run time

`run.sh` reads these from the environment; all are optional.

| | |
| --- | --- |
| `FENIX_URI=` | open a URL instead of the home screen. Nothing can type on Mir yet, so this is currently the only way to reach a page. `run.sh` also takes one as its first argument, which is what the desktop file's `%u` hands over. |
| `FENIX_RESET=1` | move the profile aside before starting (the old one is kept in the cache directory). |
| `FENIX_NO_GPU=1` | CPU raster — the first knob to flip if it dies in skia. |
| `FENIX_CDS=off` | do not use or write the class-data archive. About 2 s slower to first frame. |
| `FENIX_E10S=1` | let Gecko start content processes. The default is single-process, which is also what `user.js` pins. |
| `FENIX_EXCLUDE=` | class-path jars to leave off. Defaults to `androidx.profileinstaller`, whose startup Initializer asks the AssetManager for `assets/dexopt/baseline.prof` — an asset this APK does not have, and atlas hands `openNonAsset`'s NULL straight to `Asset_openFileDescriptor`. An ART baseline profile is meaningless on a JVM anyway. |
| `FENIX_JVMOPTS=` | extra JVM options, space separated. |

## Where everything comes from

| | |
| --- | --- |
| the framework and the launcher | [NotKit/atl-touch](https://github.com/NotKit/atl-touch) `master`, tracked as the `atl-touch` submodule |
| Gecko | [NotKit/firefox](https://github.com/NotKit/firefox) branch `atl/android-toolkit-glibc`, built with `mozconfig-atl-glibc-arm64` |
| the two tarballs | releases of this repository, pinned by tag in `build.sh` |

Nothing else is needed to build: `clickable build --arch arm64 --skip-review`
fetches the tarballs and compiles atlas from the submodule.
The icon is derived from the Fennec F-Droid launcher icon, which is F-Droid's
own community artwork rather than Mozilla's logo or wordmark, redrawn flat in
Suru style. Nothing trademarked is reproduced, but the package is still an
unofficial build and is named "Firefox (Fenix)" only as a description.

## Known limitations

Inherited from the vehicle, not from the packaging:

* **Unconfined AppArmor**, like both sibling packagings.
* **The debug variant.** Release runs R8, which this route cannot use: the class
  path needs unrenamed class names. That is also why `run.sh` seeds
  LeakCanary's preference to off — debug Fenix posts an *ongoing* "N retained
  objects" notification that Lomiri shows and no tap dismisses, and it only
  clears after a heap dump, which atlas cannot do.
* **Single process.** `user.js` pins `browser.tabs.remote.autostart` and
  friends off; `GeckoRuntimeSettings` pushes its own defaults after `omni.ja`,
  so a pref only sticks from `user.js` — and the profile only exists from the
  second run onwards.
* **No AAC and no H.264.** `user.js` keeps Gecko off the Java MediaCodec
  decoder module, because `CodecProxy` binds a service GeckoView declares as
  `android:process=":media"`, atlas runs it in-process, and
  `GeckoLoader.suppressCrashDialog`'s `MOZ_RELEASE_ASSERT(IsMediaProcess())`
  then kills the browser. ffvpx serves mp3, flac, opus, vorbis, VP8, VP9 and
  AV1; an AAC or H.264 page gets a media error instead of a SIGSEGV.
* **Nothing can be typed yet.** No input-method backend has come up on Mir on
  this stack, which is why `FENIX_URI` exists.
* **Sampled JPEG decodes may crash** if the prebuilt `libskia.so` in the sysroot
  tarball was built with `skia_use_system_libjpeg_turbo=true`; libjpeg-turbo 3.x
  segfaults in `SkJpegCodec::onGetScaledDimensions`. `PROVENANCE.md` inside the
  tarball says which build it is.
* **It is large.** `libxul.so` alone is about 150 MB stripped, the class path
  another 175 MB and the resource APK 114 MB.

## Checks worth running on the device

    # nothing unresolved, from the click's own directories
    cd /opt/click.ubuntu.com/fenix.thekit/current
    for f in lib/*.so* lib/android-translation-layer-hotspot gecko/*.so; do
        ldd "$f" | grep -H 'not found' && echo "  ^ $f"
    done

    # the run's own log, and the JVM's if it died
    tail -f ~/.cache/fenix.thekit/fenix.log
    ls ~/.cache/fenix.thekit/hs_err_*.log

    # did the class-data archive get used?
    cat ~/.cache/fenix.thekit/cds.log     # empty means it was used
