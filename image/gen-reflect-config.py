#!/usr/bin/env python3
"""Register the classes Android instantiates by *name* for reflection.

    gen-reflect-config.py <out.json> <jar> [<jar> ...]

Two whole families of class are invisible to both the tracing agent and the
closed-world analysis, because nothing in the bytecode names them:

  * every **View**, inflated by `LayoutInflater` from a name in a layout XML;
  * every **Fragment**, instantiated by `FragmentFactory.loadFragmentClass`
    from a name in the navigation graph.

A miss is a `ClassNotFoundException` at the moment the user opens that screen,
which is the worst possible place to find one -- `org.mozilla.fenix.browser.
SwipeGestureLayout` and `org.mozilla.fenix.browser.BrowserFragment` were the
first two, and they are the browser itself.

So the class hierarchy is read out of the jars and every descendant of
`android.view.View` and `androidx.fragment.app.Fragment` is registered with all
its declared constructors -- `allDeclaredConstructors` rather than a guessed
`(Context, AttributeSet)`, because the inflater picks between three shapes and a
guess would register the wrong one silently.

Generated at build time rather than committed: a payload bump adds and removes
classes, and a stale list is a list that is wrong exactly where it matters.
"""
import json
import struct
import sys
import zipfile

ROOTS = ("android/view/View", "androidx/fragment/app/Fragment")

# constant-pool tags whose entries are a fixed number of bytes after the tag
FIXED = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4,
         15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
WIDE = (5, 6)  # long and double take two constant-pool slots


def class_and_super(data):
    """(this_class, super_class) as internal names, or None if unparsable."""
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
    super_name = utf8.get(classref.get(super_i)) if super_i else None
    return (this_name, super_name) if this_name else None


def main():
    out, jars = sys.argv[1], sys.argv[2:]
    supers = {}
    for jar in jars:
        try:
            zf = zipfile.ZipFile(jar)
        except zipfile.BadZipFile:
            continue
        with zf:
            for name in zf.namelist():
                if not name.endswith(".class"):
                    continue
                pair = class_and_super(zf.read(name))
                if pair:
                    supers[pair[0]] = pair[1]

    # A class is interesting when its superclass chain reaches one of the roots.
    # Memoised, because these chains are deep and shared.
    verdict = {}

    def wanted(name):
        chain = []
        while name is not None and name not in verdict:
            if name in ROOTS:
                verdict[name] = True
                break
            parent = supers.get(name)
            if parent is None:          # unknown or java.lang.Object
                verdict[name] = False
                break
            chain.append(name)
            name = parent
        answer = verdict.get(name, False)
        for c in chain:
            verdict[c] = answer
        return answer

    picked = sorted(c for c in supers if c not in ROOTS and wanted(c))
    entries = [{"name": c.replace("/", "."), "allDeclaredConstructors": True}
               for c in picked]
    with open(out, "w") as f:
        json.dump(entries, f, indent=2)
        f.write("\n")
    print(f"reflection: {len(entries)} View and Fragment subclasses "
          f"out of {len(supers)} classes")


if __name__ == "__main__":
    main()
