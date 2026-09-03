#!/usr/bin/env python3
"""Drop from a Fenix APK what a JVM/image vehicle never reads.

The APK is a resource container here: atlas's AssetManager opens it through
libandroidfw and PackageParser reads its binary AndroidManifest.xml. No dex is
executed, the natives come from the click's own lib/, and Gecko's resources are
the unpacked GRE in gecko/ rather than assets/omni.ja.

libandroidfw takes resources.arsc three ways and only one is free:
mmapped in place (stored, 4-byte aligned), memcpy'd whole (stored, unaligned --
_FileAsset::ensureAlignment), or inflated whole (deflated -- _CompressedAsset).
So every stored entry keeps its method and its alignment here, with the same
raw zero padding in the local extra field that the shipped APK already uses.
"""
import argparse, re, sys, zipfile

DROPS = {
    'dex':   lambda n: re.fullmatch(r'classes\d*\.dex', n) is not None,
    'sig':   lambda n: n.startswith('META-INF/'),
    'lib':   lambda n: n.startswith('lib/'),
    'omni':  lambda n: n == 'assets/omni.ja',
}
ALIGN = 4

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('dst')
ap.add_argument('--drop', default='dex,sig',
                help='comma-separated: ' + ','.join(DROPS) + ' (default dex,sig)')
a = ap.parse_args()

drops = [d.strip() for d in a.drop.split(',') if d.strip()]
for d in drops:
    if d not in DROPS: sys.exit(f'unknown drop set: {d}')
def dropped(n): return any(DROPS[d](n) for d in drops)

kept = gone = 0
kept_b = gone_b = 0
with zipfile.ZipFile(a.src) as zin, \
     zipfile.ZipFile(a.dst, 'w', allowZip64=True) as zout:
    for zi in zin.infolist():
        if dropped(zi.filename):
            gone += 1; gone_b += zi.compress_size; continue
        out = zipfile.ZipInfo(zi.filename, date_time=zi.date_time)
        out.compress_type  = zi.compress_type
        out.external_attr  = zi.external_attr
        out.internal_attr  = zi.internal_attr
        out.create_system  = zi.create_system
        if zi.compress_type == zipfile.ZIP_STORED:
            # zipfile writes 30 + name + extra before the data; pad the extra so
            # the data lands on a word boundary, as zipalign does.
            here = zout.fp.tell() + 30 + len(out.filename.encode())
            out.extra = b'\0' * (-here % ALIGN)
        zout.writestr(out, zin.read(zi.filename), compress_type=zi.compress_type)
        kept += 1; kept_b += zi.compress_size

print(f'kept {kept} entries ({kept_b/1048576:.1f} MB), '
      f'dropped {gone} ({gone_b/1048576:.1f} MB) [{",".join(drops)}]')
