#!/usr/bin/env python3
"""Register the classes Android instantiates by *name* for reflection.

    gen-reflect-config.py <out-reflect.json> <out-jni.json> <libxul.so|-> <jar>...

Whole families of class are invisible to both the tracing agent and the
closed-world analysis, because nothing in the bytecode names them: every
**View** the layout inflater builds from a layout XML, every **Fragment**
`FragmentFactory.loadFragmentClass` builds from the navigation graph, every
**ViewModel** `ViewModelProvider` builds from a class literal, every
**Preference**, and the four component types the manifest names. `ROOTS` below
is the list, and each entry was added because a run died on it.

A miss is a `ClassNotFoundException` at the moment the user opens that screen,
which is the worst possible place to find one -- `org.mozilla.fenix.browser.
SwipeGestureLayout` and `org.mozilla.fenix.browser.BrowserFragment` were the
first two, and they are the browser itself.

So the class hierarchy is read out of the jars and every descendant of those
roots is registered with all its declared constructors -- `allDeclaredConstructors` rather than a guessed
`(Context, AttributeSet)`, because the inflater picks between three shapes and a
guess would register the wrong one silently.

A second family: **span array types**. `Spannable.getSpans()` does
`Array.newInstance(type, n)`, and an array class instantiated reflectively has
to be registered for unsafe allocation -- `RegistrableDomainSpan[]` was an
`IllegalArgumentException` from inside Compose while the toolbar was drawing.

A third: GeckoView's **@WrapForJNI classes**, which need both configs. Java
side, `NativeQueue` dispatches a queued call with `getDeclaredMethod(name,
argTypes)` -- `GeckoSession$Window.attachEditable` was a `NoSuchMethodException`
the moment the first tab opened. Native side, libxul reaches the same members
with `GetMethodID`, which is JNI rather than reflection and fails separately --
`GeckoRuntime.unlockScreenOrientation` killed the Gecko thread. Any class
carrying one of Gecko's four JNI/reflection marker annotations gets its whole
surface kept in both; there are about a hundred of them.

A fourth, JNI only: **the class names libxul carries**. `FindClass` takes an
internal name out of the binary's string table, so the names are all there to
be read -- 46 of them, from `java/lang/IllegalStateException` (which Gecko
throws from `runUiThreadCallback`, and whose absence killed the run a tenth of
a second after the first paint) to `android/media/MediaCodec`. Names not on the
class path are dropped, so a framework class atlas does not have is not
registered, and a JDK name is registered for `FindClass` alone -- giving
`java.lang.Class` all its methods makes `getClassLoader` reachable, and the
class loader drags a `JarFile` into the image heap.

Generated at build time rather than committed: a payload bump adds and removes
classes, and a stale list is a list that is wrong exactly where it matters.
"""
import json
import re
import struct
import sys
import zipfile

# Everything Android builds from a name rather than from a `new`.
ROOTS = (
    "android/view/View",                # the layout inflater, from a layout XML
    "androidx/fragment/app/Fragment",   # FragmentFactory, from the nav graph
    "androidx/lifecycle/ViewModel",     # ViewModelProvider, from a class literal
    "androidx/preference/Preference",   # the preference inflater, from an XML
    "android/app/Activity",             # the manifest
    "android/app/Service",
    "android/app/Application",
    "android/content/BroadcastReceiver",
    "android/content/ContentProvider",
)

# Span types get one more registration, of their *array* class. Text.getSpans()
# does Array.newInstance(type, n), and an array type instantiated reflectively
# has to be registered for unsafe allocation or the run gets
#
#     IllegalArgumentException: Class ...RegistrableDomainSpan[] is instantiated
#     reflectively but was never registered
#
# from inside Compose, i.e. while the toolbar is being drawn. The roots are the
# marker types every span implements; the name test catches the ones whose
# marker is in a jar this scan does not see.
SPAN_ROOTS = ("android/text/style/CharacterStyle", "android/text/style/ParagraphStyle",
              "android/text/ParcelableSpan", "android/text/NoCopySpan",
              "android/text/style/UpdateAppearance")

# Gecko's markers for "this is reached from native code or by name". The
# annotations are dropped at runtime, but their descriptor stays in the
# constant pool of every class that uses one, which is enough to find them.
JNI_MARKERS = ("Lorg/mozilla/gecko/annotation/WrapForJNI;",
               "Lorg/mozilla/gecko/annotation/JNITarget;",
               "Lorg/mozilla/gecko/annotation/ReflectionTarget;",
               "Lorg/mozilla/gecko/annotation/WebRTCJNITarget;")

# An internal class name in a binary's string table: FindClass's argument.
XUL_NAME = re.compile(rb"(?:java|javax|android|androidx|org/mozilla)"
                      rb"(?:/[A-Za-z_$][A-Za-z0-9_$]*)+")

# constant-pool tags whose entries are a fixed number of bytes after the tag
FIXED = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4,
         15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
WIDE = (5, 6)  # long and double take two constant-pool slots


def read_class(data):
    """(this_class, [superclass and interfaces], marked) or None.

    `marked` is true when the constant pool mentions one of JNI_MARKERS.
    """
    if len(data) < 10 or data[:4] != b"\xca\xfe\xba\xbe":
        return None
    count = struct.unpack_from(">H", data, 8)[0]
    utf8 = {}
    classref = {}
    marked = False
    i, pos = 1, 10
    while i < count:
        tag = data[pos]
        pos += 1
        if tag == 1:
            n = struct.unpack_from(">H", data, pos)[0]
            s = data[pos + 2:pos + 2 + n].decode("utf-8", "replace")
            utf8[i] = s
            marked = marked or s in JNI_MARKERS
            pos += 2 + n
        elif tag in FIXED:
            if tag == 7:
                classref[i] = struct.unpack_from(">H", data, pos)[0]
            pos += FIXED[tag]
        else:
            return None  # an unknown tag means the rest of the offsets are junk
        i += 2 if tag in WIDE else 1
    this_i, super_i = struct.unpack_from(">HH", data, pos + 2)
    this_name = utf8.get(classref.get(this_i))
    if not this_name:
        return None
    parents = []
    if super_i:
        sup = utf8.get(classref.get(super_i))
        if sup:
            parents.append(sup)
    n_ifaces = struct.unpack_from(">H", data, pos + 6)[0]
    for k in range(n_ifaces):
        iface = utf8.get(classref.get(struct.unpack_from(">H", data, pos + 8 + 2 * k)[0]))
        if iface:
            parents.append(iface)
    return this_name, parents, marked


def xul_classes(path):
    """The internal class names FindClass could be called with, from libxul."""
    if path == "-":
        return set()
    with open(path, "rb") as f:
        return {m.group().decode() for m in XUL_NAME.finditer(f.read())}


def main():
    out, out_jni, xul, jars = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    parents = {}
    jni = set()
    for jar in jars:
        try:
            zf = zipfile.ZipFile(jar)
        except zipfile.BadZipFile:
            continue
        with zf:
            for name in zf.namelist():
                if not name.endswith(".class"):
                    continue
                info = read_class(zf.read(name))
                if not info:
                    continue
                parents[info[0]] = info[1]
                if info[2]:
                    jni.add(info[0])

    def descends_from(name, roots, seen=None):
        """Does name reach any of roots through extends or implements?"""
        if name in roots:
            return True
        seen = seen if seen is not None else set()
        if name in seen:
            return False
        seen.add(name)
        return any(descends_from(p, roots, seen) for p in parents.get(name, ()))

    picked = sorted(c for c in parents
                    if c not in ROOTS and descends_from(c, ROOTS))
    entries = [{"name": c.replace("/", "."), "allDeclaredConstructors": True}
               for c in picked]

    spans = sorted(c for c in parents
                   if c.rsplit("/", 1)[-1].endswith("Span")
                   or descends_from(c, SPAN_ROOTS))
    entries += [{"name": c.replace("/", ".") + "[]", "unsafeAllocated": True}
                for c in spans]

    # A name the class path does not have would be registered as unresolvable;
    # java.* is not on the class path but is always there.
    native = {c for c in xul_classes(xul)
              if c in parents or c.startswith(("java/", "javax/"))}
    # The JDK names are wanted for FindClass alone. Giving java.lang.Class all
    # its methods makes getClassLoader reachable, and the class loader drags a
    # JarFile into the image heap, which the builder refuses.
    jdk = {c for c in native if c.startswith(("java/", "javax/"))}
    jni |= native - jdk
    gecko = [{"name": c.replace("/", "."), "allDeclaredMethods": True,
              "allDeclaredFields": True, "allDeclaredConstructors": True}
             for c in sorted(jni)]
    gecko += [{"name": c.replace("/", ".")} for c in sorted(jdk)]
    entries += gecko
    for path, data in ((out, entries), (out_jni, gecko)):
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
    print(f"reflection: {len(picked)} name-instantiated classes, "
          f"{len(spans)} span array types, {len(jni)} JNI classes and "
          f"{len(jdk)} JDK names for FindClass, out of {len(parents)} classes")


if __name__ == "__main__":
    main()
