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
