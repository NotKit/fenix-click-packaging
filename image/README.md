# image — Fenix compiled ahead of time

The click runs Fenix on a bundled HotSpot: 361 jars on a class path, loaded,
parsed, verified and linked at every start. This directory asks the other
question — what if the Java is compiled ahead of time instead? — by building a
**GraalVM native image** of that same class path as a shared library exporting
the JNI Invocation API, which atlas's `android-translation-layer-image` loads
in place of `libjvm.so`.

    HAX=…/api-impl_classes.jar SHIMJAR=…/shim.jar APPCP=…/classpath \
      GRAALVM_HOME=… ./image/build-image.sh

The inputs are the SDK tarball's framework jar, the payload tarball's class
path and `shim/build.sh`'s jar — the same three the HotSpot click assembles, so
the image is over the same code.

## Where the build has to run

`native-image` **cannot cross-compile**: the image is for the machine the
builder runs on. Everything fed to it here is architecture-neutral (class
files, JSON), so an aarch64 image is this script on an aarch64 machine with
about 16 GB and a C toolchain — nothing more, but nothing less. That machine
was the blocker for a month: the phone has `ld` and `objcopy` but no C compiler
and 7.2 GB against a builder that peaks at 8 GB, qemu-user runs the builder
**38x** slower, and Houdini does not finish at all. GitHub's `ubuntu-24.04-arm`
runners are the machine, and the `image` job in `.github/workflows/build.yml`
is how it is rented.

`firefox-atl`'s `jvm-run/image/NOTES.md` has the measurements behind all of
that, and is the long-form account of everything here.

## The two config directories

`ni-config/` is GraalVM's tracing agent over one full desktop boot of this same
class path, and **is never hand-edited** — a traced call site is only registered
for the arms that one run happened to take. `extra-config/` is the other half:
entries an image *run* proved the trace could not see, each with the failure
that justifies it in its README.

`initialize-at-build-time.txt` answers, one name per line, native-image's
complaints that a class it expected at run time was initialised during the
build. Nothing under `android.*`, `org.mozilla.*` or `mozilla.*` belongs in it
without reading the class: those are the ones whose `<clinit>` can read a `-D`
property the build host cannot answer. `android.os.Build$VERSION` and
`android.os.SystemProperties` are pinned to run time for the same reason —
`SDK_INT` is a `static final int`, and a build-time value is constant-folded
into every `SDK_INT >= N` branch in the app.

## What the closed world exposes that HotSpot hides

Registering a class for JNI or reflection **loads** it, and loading resolves
every signature type. So an `android.*` type atlas does not have is invisible on
the HotSpot vehicle and fatal under an image. Two such types and an
unregisterable JCE provider were the first three walls, and all three are fixed
in atlas (`8815f1d7`, `86480a1d`); `gapclasses/` holds the stubs for the first
two and `build-image.sh` compiles them **only** for a framework that is missing
them, so an SDK new enough to carry the real classes leaves the directory
unused.
