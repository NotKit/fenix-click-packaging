# Hand-written metadata the trace could not see

`/var/tmp/atl-jvm/ni-config` is the agent's output and is never edited: a traced
call site is only registered for the arms that one run happened to take. This
directory is the other half -- entries added because an image run failed on
them, one file per config kind, each entry with the failure that justifies it.

* `org.mozilla.fenix.HomeActivity.onBackPressed` --
  `android_app_Activity.c:98` does `GetMethodID(env, current_activity_class,
  "onBackPressed", "()V")` on the *concrete* activity class every time the back
  gesture is wired up. The trace registered the method on `android.app.Activity`
  and on `androidx.activity.ComponentActivity` but only the *class* for
  `HomeActivity`, so the image died with
  `Exception in thread "main": java.lang.NoSuchMethodError:
  org.mozilla.fenix.HomeActivity.onBackPressed()V` -- a JNI miss, which is a
  NoSuchMethodError rather than the NoSuchMethodException a reflective miss
  gives.

* `java.io.FileDescriptor` (the no-arg constructor and the `fd` field) and
  `android.system.ErrnoException` (the `(String, int)` constructor) --
  `shim/native/port_shim.c` looks all three up by JNI: `fdFor()` builds a
  `FileDescriptor` and pokes the private field, and every failure path throws an
  `ErrnoException`. The trace never saw them because on the desktop the run died
  at the keystore wall first; with that wall gone the phone reached
  `GeckoRuntime.startCrashHelper`, which does `ParcelFileDescriptor.dup` ->
  `Os.dup` -> `Posix.fdFor`, and got

      java.lang.NoSuchMethodError: java.io.FileDescriptor.<init>()V
        at ...JNIFunctions.GetMethodID(JNIFunctions.java:431)
        at libcore.io.Posix.fdFor(Native Method)

* Five more of atlas's own JNI call sites, found by reading
  `src/api-impl-jni/` rather than by another failing run:
  `android.view.Display.setWindowSize(int,int)` (`ATLWindow.c:1346`, a
  `GetStaticMethodID` -- every publisher of the window size goes through it),
  `android.view.ViewRootImpl.dispatchConfigurationChanged()`,
  `android.app.Activity.detachWindowViews()`, `android.net.Network.<init>()`
  and `android.graphics.SurfaceTexture.postFrameAvailableFromNative()`. The
  trace registered 14 of ViewRootImpl's 15 and none of Display's, because one
  boot does not take every arm.

  `detachWindowViews` is repeated on `HomeActivity` for the reason
  `onBackPressed` is: atlas does `GetObjectClass(activity)`, so the lookup is on
  the concrete class.

`reflect-config.json` here has one entry: **`java.io.FileDescriptor`'s `fd`
field**. atlas's `android.atl.FileDescriptorUtils` reaches the descriptor
through libcore's `getInt$` when the runtime has it and falls back to the
private field otherwise -- and under an image an unregistered field simply is
not found, so the fallback failed too and `ParcelFileDescriptor.getFd` threw
`UnsupportedOperationException: cannot read a FileDescriptor on this runtime`.
Registering it for JNI is not enough; this path is reflection.

Two things `build-image.sh` generates rather than keeps here:

* **Every `*Fragment` class on the class path**, with its no-arg constructor,
  into `generated-reflect-config.json`. `FragmentFactory.loadFragmentClass`
  does `Class.forName(name)` then `getConstructor()` on a name that comes from
  the navigation graph, so neither the trace nor the analysis can see it, and an
  unregistered fragment is a `ClassNotFoundException` at the moment a user opens
  that screen. Generated from the jars so a payload bump cannot leave a stale
  list behind. The first one to surface was
  `org.mozilla.fenix.browser.BrowserFragment` -- i.e. the browser itself.
* **The AndroidKeyStore provider, installed into the builder's own provider
  list** by `feature/fenixni/KeyStoreProviderFeature.java`. See that file: this
  is what `-H:AdditionalSecurityProviders` does *not* do, and without it the
  keystore wall comes back the moment android-components calls
  `KeyGenerator.getInstance`.
