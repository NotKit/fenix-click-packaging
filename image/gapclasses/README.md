# Framework types atlas lacks, that only a closed world needs

Registering a class for JNI or reflection makes native-image *load* it, which
resolves every type in every method signature. HotSpot never does that -- it
resolves a signature type when the method is first called -- so a missing
`android.*` type is invisible on the HotSpot vehicle and fatal on the image:
the registration degrades to

    Warning: Could not register method X for reflection.
    Reason: java.lang.NoClassDefFoundError: android/...

and the JNI lookup atlas makes at run time then throws NoSuchMethodError.

Each file here is a **bug in atlas**, not a fix. They are empty declarations:
nothing calls them, they exist so a signature resolves.

Both are fixed upstream now — atl-touch master `8815f1d7`, with real bodies and
the `Activity` callbacks that take them — so this directory is scaffolding until
the vehicle's `hax.jar` is rebuilt from master, not a permanent home.

* `android/app/assist/AssistContent.java` -- `HomeActivity` overrides
  `onProvideAssistContent(AssistContent)`; without the type, registering
  `HomeActivity.onBackPressed` fails and atlas'
  `GetMethodID(current_activity_class, "onBackPressed", "()V")`
  (`android_app_Activity.c:98`) throws.
