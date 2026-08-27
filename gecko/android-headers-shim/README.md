# android-headers-shim — the NDK headers this build compiles against

`--with-android-headers=` points here (see `mozconfig-atl-glibc*` in the Gecko
tree). Gecko's android-toolkit code includes `<android/*.h>`, `<media/Ndk*.h>`
and the GLES headers, which come free from the NDK sysroot on a real Android
build and have to be put on the include path by hand here.

`android/` and `media/` are one-line wrappers — the `ndk-shim.h` prologue, then
the real header from `ndk/`. The indirection exists so the `__ANDROID_API__` /
`__INTRODUCED_IN` prologue is only in force inside the NDK headers themselves.
Only those two directories are exposed: the full android-headers tree also
carries `linux/`, `system/` and `cutils/`, which would shadow the host's own
kernel headers.

`GLES2/`, `GLES3/` and `KHR/` are symlinks to `/usr/include`: the host's Mesa
headers, which is what the translation layer renders through.

## The headers in `ndk/`

Committed as real files, so a checkout compiles with no NDK installed. Three
sources, each file keeping its own Apache-2.0 notice:

| files | from |
| --- | --- |
| 9 `android/` headers the layer itself implements against | ubports `android-headers`, the `30` tree |
| 15 further `android/` headers | an NDK sysroot's `usr/include` |
| 10 `media/Ndk*.h` | NDK r27's sysroot — newer than the layer's copies, and unlike them they parse as C |

`android/native_window_jni.h` is written by `regenerate.sh`: no NDK copy carries
the `ANativeWindow_fromSurfaceTexture` variant the layer implements.

## Refreshing

Only needed when the layer grows an entry point or the API level moves:

    ATL_HEADERS=<android-headers>/30 \
    NDK_HEADERS=<ndk sysroot>/usr/include \
    NDK_SYSROOT=<ndk sysroot>/usr/include \
      ./regenerate.sh

It rewrites `ndk/`, the wrappers and the three GLES links, and prints how many
headers it copied. Changing what is in `ndk/` changes the gap list the link
shim derives, so re-run `../android-libs-shim/regenerate.sh` afterwards.
