# android-libs-shim — the NDK link and trace shim

`regenerate.sh` builds what an Android NDK sysroot would supply and this system
does not: `liblog`, `libandroid`, `libjnigraphics`, `libmediandk`, plus
`libatlndkstub.so`, one stub per NDK entry point that neither glibc nor ATL's
`libandroid.so.0` defines (`ndk-gap.txt`, 283 entries).

Rebuild with `./regenerate.sh`. `libxul` does **not** need relinking: its
`DT_NEEDED` records the plain soname `libatlndkstub.so`, so a rebuild in place
is picked up at the next run.

## The stubs record themselves

Every stub logs its own name — to stderr and, unless disabled, to an
append-only file — and then aborts. `ATL_NDK_STUB_SOFT=1` makes it return zero
and continue instead, so **one** run enumerates the whole startup path rather
than reporting one symbol per run.

| variable | effect |
|---|---|
| `ATL_NDK_STUB_LOG=<path>` | append-only trace file. Default `/tmp/atl-ndk-stub-trace.log` (build-time `ATL_NDK_STUB_LOG_DEFAULT`). `-` disables the file; stderr always gets the lines. |
| `ATL_NDK_STUB_SOFT=1` | every stub returns zero and continues. A comma-separated prefix list instead of `1` softens only those (`AFont_,ATrace_`). |
| `ATL_NDK_STUB_ABORT_ON=...` | comma-separated prefixes that abort even in soft mode. |
| `ATL_NDK_STUB_VERBOSE=1` | log every call, not just the first per symbol. |
| `ATL_NDK_STUB_BACKTRACE=1` | dump up to 16 frames per logged call. |

Line format, one per first call:

```
ATL-NDK-STUB <name> ret=0x<caller addr> tid=<tid> calls=<n> soft|ABORT
```

and at exit, for every symbol that was reached at all:

```
ATL-NDK-STUB-SUMMARY <name> calls=<n>
ATL-NDK-STUB-SUMMARY total reached=<n> of 283 pid=<pid>
```

The summary is written from a destructor, so it appears on a clean exit but not
after an `abort()`. Logging is `write(2)` to a fd throughout: the stubs are
reachable before `main`, from library constructors and from any thread.

## Where zero is a lie

The stubs keep their `void(void)` link-time shape, so soft mode zeroes the
return registers by hand (tail call into `atl_ndk_stub_zero_tail`). For a
pointer-returning entry point that is the honest "unavailable" answer. For the
two families below it is not, and the caller will use uninitialised memory:

* **`media_status_t` functions**: `AMEDIA_OK` is 0, so zero reads as *success*
  while the out-parameter was never written. `AImageReader_newWithUsage`,
  `AImageReader_getWindow`, `AImageReader_acquireNextImageAsync`,
  `AImage_getHardwareBuffer` and the whole `AMediaDrm_*` set are in this class.
* **`AHardwareBuffer_allocate` / `_lock`**: `int`, 0 = success, `outBuffer` /
  `outVirtualAddress` untouched.
* `AFont_getFontFilePath` is declared `const char* _Nonnull`; NULL will be
  passed straight to string code.

Enumerate first with a plain `ATL_NDK_STUB_SOFT=1` — it walks the furthest,
and a crash afterwards is itself information. Then re-run with the lying
families made fatal, to see which of them the startup path really enters:

```sh
ATL_NDK_STUB_SOFT=1 \
ATL_NDK_STUB_ABORT_ON=AImageReader_,AImage_,AHardwareBuffer_,AMediaDrm_,AMediaCrypto_new,AFont_getFontFilePath \
ATL_NDK_STUB_LOG=/tmp/atl-ndk-stub-trace.log ...
```

## What the stub library actually covers

Of the 283 stubs, `libxul` imports **38**; it imports 13 further NDK symbols
that ATL's own `libandroid.so.0` defines (`ANativeWindow_*`, `AndroidBitmap_*`,
`AMediaCodecCryptoInfo_*`). `libmozavcodec.so` imports 35 (the `AMediaCodec_*`
set), `libmozavutil.so` one. The remaining stubs are declared by the NDK
headers and referenced by nothing in this build.

One NDK use is invisible to the trace: `netwerk/system/android/`
`AndroidNetworkBlockedReason.cpp` `dlopen("libandroid.so")` +
`dlsym("android_getnetworkblockedreason")`. Here `libandroid.so` is a GNU ld
script, so the `dlopen` fails — which that code already treats as "device does
not have the API".
