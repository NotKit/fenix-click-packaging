#!/usr/bin/env python3
"""Register the classes Android instantiates by *name* for reflection.

    gen-reflect-config.py <out.json> <jar> [<jar> ...]

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

A third, smaller family: **span array types**. `Spannable.getSpans()` does
`Array.newInstance(type, n)`, and an array class instantiated reflectively has
to be registered for unsafe allocation -- `RegistrableDomainSpan[]` was an
`IllegalArgumentException` from inside Compose while the toolbar was drawing.

Generated at build time rather than committed: a payload bump adds and removes
classes, and a stale list is a list that is wrong exactly where it matters.
"""
import json
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

# constant-pool tags whose entries are a fixed number of bytes after the tag
FIXED = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4,
         15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
WIDE = (5, 6)  # long and double take two constant-pool slots


def class_parents(data):
    """(this_class, [superclass and interfaces]) as internal names, or None."""
    if len(data) < 10 or data[:4] != b"\xca\xfe\xba\xbe":
        return None
    count = struct.unpack_from(">H", data, 8)[0]
    utf8 = {}
    classref = {}
    i, pos = 1, 10
    while i < count:
        tag = data[pos]
        pos += 1
        if tag == 1:
            n = struct.unpack_from(">H", data, pos)[0]
            utf8[i] = data[pos + 2:pos + 2 + n].decode("utf-8", "replace")
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
    return this_name, parents


def main():
    out, jars = sys.argv[1], sys.argv[2:]
    parents = {}
    for jar in jars:
        try:
            zf = zipfile.ZipFile(jar)
        except zipfile.BadZipFile:
            continue
        with zf:
            for name in zf.namelist():
                if not name.endswith(".class"):
                    continue
                pair = class_parents(zf.read(name))
                if pair:
                    parents[pair[0]] = pair[1]

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
    with open(out, "w") as f:
        json.dump(entries, f, indent=2)
        f.write("\n")
    print(f"reflection: {len(picked)} name-instantiated classes and "
          f"{len(spans)} span array types, out of {len(parents)} classes")


if __name__ == "__main__":
    main()
