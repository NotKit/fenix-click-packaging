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
| **firefox-atl** | where Gecko, the class path, the shim and the runners are developed; `gecko/` here is its publishable half |

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
    run.sh          the device launcher. It sets the environment up and then
                    execs the launcher, so the process Lomiri started IS the
                    browser: suspend, resume and close reach the JVM directly.
    user.js         the Gecko prefs the profile is seeded with

The profile lives in `~/.local/share/fenix.thekit` and nothing removes it;
`FENIX_RESET=1` moves it aside. Everything regenerable — the AppCDS archive, the
class-path symlink farm, `$ANDROID_ROOT/fonts` and the log — is in
`~/.cache/fenix.thekit`.

## The two tarballs

The click is assembled, not compiled. Two prebuilt inputs carry everything
heavy, each pinned by tag and sha256 in `build.sh`.

**`atl-sdk-arm64.tar.zst`** (36 MB) — atlas and its whole native chain, a
release asset of [atl-touch](https://github.com/NotKit/atl-touch) built by that
repository's own CI on a native arm64 runner (`ci/build-sdk.sh`, tagged
`sdk-<atlas-sha>`). It carries the HotSpot launcher,
`libtranslation_layer_main.so`, `libandroid.so.0`, `api-impl_classes.jar`,
`framework-res.apk`, the Roboto faces, and what Ubuntu Touch does not ship:
`art_standalone`'s `libandroidfw` and friends, GLFW 3.4 and `libskia.so`.

The framework jar this vehicle uses is `api-impl_classes.jar`, the javac output.
The `api-impl.jar` beside it under `lib/java/dex` is the same classes after d8 —
a `classes.dex` HotSpot cannot read.

    FENIX_SDK_TAG=sdk-<sha> FENIX_SDK_DIR=<unpacked tree>   # to override either

**`fenix-jvm-payload-arm64.tar.zst`** (205 MB) — Gecko for aarch64, Fenix's
class path, the resource APK and the aarch64 megazord. This is the half that
changes with every Gecko or Fenix build, and `gecko/` builds it: the shim trees
Gecko compiles and links against, and the scripts that stage the objdir, build
Fenix's class path and pack the result. Gecko itself is
[NotKit/firefox](https://github.com/NotKit/firefox) branch
`atl/android-toolkit-glibc`, configured by that tree's own
`mozconfig-atl-glibc-arm64`.

`.github/workflows/payload.yml` runs the whole sequence on an ordinary x86_64
runner and publishes the tarball; `gecko/README.md` is the same sequence by
hand. `megazord.yml` builds the one native Mozilla does not publish for this
target, on an arm64 runner, a few times a year.

Upload anything built by hand with `gh release create <tag> dist/<file>
dist/<file>.sha256`, then point `build.sh`'s default tag at it — the payload
workflow can open that bump as a PR itself.

For local iteration neither has to be published: `FENIX_SYSROOT_DIR` and
`FENIX_PAYLOAD_DIR` name unpacked trees and are used as-is.

### A third, optional: the ahead-of-time image

**`fenix-image-arm64.tar.zst`** — Fenix's whole class path compiled by GraalVM's
`native-image` into one shared library that exports the JNI Invocation API, so
atlas's `android-translation-layer-image` creates its VM from it and there is no
class path, no class loading and nothing for CDS to cache. `image/` is the
build; the `image` job in `.github/workflows/build.yml` runs it.

It has to be built on an **aarch64 machine**: `native-image` cannot
cross-compile, and every attempt to fake that failed — the phone has no C
compiler and 7.2 GB against an 8 GB builder, qemu-user runs the builder 38x
slower, and Houdini does not finish at all. GitHub's `ubuntu-24.04-arm` runners
are the machine, which is why this exists at all.

`FENIX_IMAGE_TAG` in `build.sh` pins it, blank means no image travels, and a
click refuses an image built over a different SDK or payload than it ships —
an image *is* the framework and the class path, so a mismatch would surface as
a wrong class at run time rather than as a build error. With one bundled, the
click still carries the JVM and the jars, and `FENIX_VM=image` picks the other
vehicle.

## Building

    clickable build --arch arm64 --skip-review
    clickable install --ssh <device>

There is no submodule and no atlas build: `build.sh` downloads the SDK tag it
pins and unpacks it. To test an unreleased atlas, point `FENIX_SDK_DIR` at a
tree built by atl-touch's `ci/build-sdk.sh`.

`--skip-review` because the package fails two `click-review` checks by design,
both shared with the sibling packagings:

* `security:template_valid: 'unconfined' not allowed` — a JVM plus a browser
  engine needs far more than the click templates grant. This blocks an OpenStore
  submission, not a local install.
* `lint:hardcoded_paths: '/opt/click.ubuntu.com/' in run.sh` — deliberate: the
  launcher prefers the version-independent `current` symlink and falls back to
  its own directory.

`device-libs.txt` is the device's own `ldconfig -p`. `build.sh` bundles every
`DT_NEEDED` that is not in it, transitively, out of the SDK and the container,
and **fails** if something is in neither — which is what stops "it linked in
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
| `FENIX_VM=image` | start the ahead-of-time image instead of the bundled HotSpot. Only in a click built with an image pinned; `FENIX_CDS` and `FENIX_EXCLUDE` do nothing there, since there is no class path. |

## Where everything comes from

| | |
| --- | --- |
| the framework and the launcher | [NotKit/atl-touch](https://github.com/NotKit/atl-touch), as its `sdk-<sha>` release asset |
| Gecko | [NotKit/firefox](https://github.com/NotKit/firefox) branch `atl/android-toolkit-glibc`, built with `mozconfig-atl-glibc-arm64` by `gecko/` here |
| both tarballs | pinned by tag and sha256 in `build.sh` |

Nothing else is needed to build: `clickable build --arch arm64 --skip-review`
fetches both and assembles them.
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
* **Sampled JPEG decodes may crash** if the `libskia.so` in the SDK was built
  with `skia_use_system_libjpeg_turbo=true`; libjpeg-turbo 3.x segfaults in
  `SkJpegCodec::onGetScaledDimensions`. `meta/sdk-manifest.json` inside the
  tarball records which skia it is.
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
