# Where this comes from

The scripts here are the publishable half of the **firefox-atl** working tree,
where this port is developed. They were reorganised rather than copied: that
tree's `route-b-run/`, `jvm-run/fenixbuild/` and `jvm-run/arm64/` also carry the
harnesses, probes and device runners the bring-up needed, and none of that is
part of a build.

| here | there | change |
| --- | --- | --- |
| `stage-gecko.sh` | `route-b-run/setup.sh` + `stage-arm64-payload.sh` | the `omni.ja` step and the strip-and-verify step only; the GeckoView shell APK, the device run scripts and the host-side pieces are gone |
| `atl-defaults.js` | the pref block `route-b-run/setup.sh` writes | unchanged prefs |
| `build-mozglue.sh` | `route-b-run/install-mozglue.sh` | cross link only; it no longer installs into an atlas build directory and writes no symlinks, because `make-payload.sh` retires them |
| `mozglue-selfglobal.c` | `route-b-run/mozglue-selfglobal.c` | verbatim, renamed symbol |
| `fenix/*` | `jvm-run/fenixbuild/*` | `env.sh` folded into the arguments; the verification scripts stayed there |
| `megazord/*` | `jvm-run/arm64/build-{nss,megazord}-arm64.sh` | paths parameterised; the gyp virtualenv is made rather than required |
| `android-headers-shim/` | same name | `ndk/` is committed as real files instead of symlinks into two NDKs, so a checkout builds with no NDK installed |
| `android-libs-shim/` | same name | sources only; the ld scripts named an absolute path on one machine and are now written by `regenerate.sh` |

Both shim trees were checked by regenerating them here and diffing: the header
tree came back identical, and the arm64 link shim came back byte-identical in
all seven outputs, `libatlndkstub.so` and `liblog.so` included.

`android-libs-shim-arm64/` is not committed — it is generated, see README.md.
