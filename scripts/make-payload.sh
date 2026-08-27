#!/bin/bash
# Assemble the Fenix/Gecko payload and pack it as
# fenix-jvm-payload-arm64.tar.zst for a GitHub release.
#
#   scripts/make-payload.sh --gecko DIR --classpath DIR --apk FILE \
#                           --megazord FILE [--mozglue FILE] [--version STR] \
#                           [--out FILE]
#
# The four inputs are built by ../gecko, which documents each one; none of them
# can be produced inside a click build container, and mozilla-central is far too
# large to make a submodule of.
#
#   --gecko      the staged Gecko tree for aarch64: libxul.so, the NSS set and
#                dist/bin's chrome/, components/, modules/ ...
#                (gecko/stage-gecko.sh).
#   --mozglue    libmozglue.so (gecko/build-mozglue.sh).  It is put INTO
#                gecko/ here: GeckoLoader putenvs MOZ_ANDROID_LIBDIR from
#                wherever it found libmozglue, and APKOpen then dlopens
#                libnss3, libnspr4, libplc4 and libmozsqlite3 out of that same
#                directory -- which is where they already are. That also
#                retires the four device-absolute symlinks the staged payload
#                carries beside it. Defaults to gecko/libmozglue.so if it is
#                already there.
#   --classpath  the ~360 jars Fenix compiles to for a JVM class path
#                (gecko/fenix/build-classpath.sh).
#   --apk        the resource container: the Gradle APK with the objdir's
#                omni.ja put back in (gecko/fenix/stage-apk.sh). Its dex
#                and its lib/ are inert on a JVM class path; atlas needs it for
#                the binary AndroidManifest and resources.arsc.
#   --megazord   libmegazord.so built for aarch64 (gecko/megazord/
#                build-megazord.sh). appservices publishes linux-x86-64
#                and darwin only.
#
# Everything here is architecture-correct or architecture-independent; the
# script checks rather than trusts.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GECKO=""; CLASSPATH=""; APK=""; MEGAZORD=""; MOZGLUE=""; VERSION=""; BUILDID=""
OUT="$HERE/dist/fenix-jvm-payload-arm64.tar.zst"

while [ $# -gt 0 ]; do
	case "$1" in
	--gecko)     GECKO="$2"; shift ;;
	--classpath) CLASSPATH="$2"; shift ;;
	--apk)       APK="$2"; shift ;;
	--megazord)  MEGAZORD="$2"; shift ;;
	--mozglue)   MOZGLUE="$2"; shift ;;
	--version)   VERSION="$2"; shift ;;
	--out)       OUT="$2"; shift ;;
	*) echo "usage: see the header of $0" >&2; exit 2 ;;
	esac
	shift
done
for v in GECKO CLASSPATH APK MEGAZORD; do
	[ -n "${!v}" ] || { echo "missing --$(echo "$v" | tr A-Z a-z)" >&2; exit 2; }
done

[ -n "$MOZGLUE" ] || MOZGLUE="$GECKO/libmozglue.so"
for f in "$GECKO/libxul.so" "$GECKO/libnss3.so" "$APK" "$MEGAZORD" "$MOZGLUE"; do
	[ -e "$f" ] || { echo "missing input: $f" >&2; exit 1; }
done
jars=$(find "$CLASSPATH" -maxdepth 1 -name '*.jar' | wc -l)
[ "$jars" -ge 100 ] || { echo "only $jars jars in $CLASSPATH" >&2; exit 1; }

for f in "$GECKO/libxul.so" "$MOZGLUE" "$MEGAZORD"; do
	case "$(file -b "$f")" in *"ARM aarch64"*) ;;
		*) echo "$f is not aarch64" >&2; exit 1 ;; esac
done
listing="$(unzip -l "$APK")" || { echo "$APK is not a zip" >&2; exit 1; }
for entry in AndroidManifest.xml resources.arsc assets/omni.ja; do
	grep -q "$entry" <<<"$listing" || { echo "$APK has no $entry" >&2; exit 1; }
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/natives/megazord"
# -L resolves symlinks into real files, because the staged tree's were written
# for the phone's paths. A few of them dangle even there -- objdir build tools
# (nsinstall) and default.locale, which points out of dist/bin into the source
# tree -- and none of them is loaded at run time, so they are dropped by name
# rather than silently turned into a copy error.
dangling=()
while IFS= read -r l; do dangling+=(--exclude="/$l"); echo "dropping dangling symlink: gecko/$l"; done 	< <(cd "$GECKO" && find . -xtype l -printf '%P\n' | sort)
rsync -aL --exclude='*.dbg' "${dangling[@]+"${dangling[@]}"}" "$GECKO/" "$WORK/gecko/"
cp -L "$MOZGLUE" "$WORK/gecko/libmozglue.so"
rsync -a "$CLASSPATH/" "$WORK/classpath/"
cp "$APK" "$WORK/fenix.apk"
cp "$MEGAZORD" "$WORK/natives/megazord/libmegazord.so"

# dist/bin/application.ini is not read at run time (Gecko says so in its own
# header) but it is the objdir's own record of what was built, which is exactly
# what the click's version should be.
if [ -z "$VERSION" ]; then
	VERSION="$(sed -n 's/^Version=//p' "$GECKO/application.ini" 2>/dev/null | head -1)"
	BUILDID="$(sed -n 's/^BuildID=//p' "$GECKO/application.ini" 2>/dev/null | head -1)"
fi
[ -n "$VERSION" ] || VERSION="0.0.0"

cat >"$WORK/PAYLOAD.txt" <<PAY
version=$VERSION
buildid=${BUILDID:-unknown}
packed=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gecko=$GECKO
classpath=$CLASSPATH ($jars jars)
apk=$APK
megazord=$MEGAZORD
mozglue=$MOZGLUE
PAY

# -19 for a release upload; FENIX_ZSTD_LEVEL=3 while iterating -- this is
# most of a gigabyte and the difference is minutes.
mkdir -p "$(dirname "$OUT")"
tar -C "$WORK" -c . | zstd -T0 "-${FENIX_ZSTD_LEVEL:-19}" -o "$OUT" -f
# Relative name, so the file is checkable with `sha256sum -c` next to the
# tarball rather than only at the path it was packed at.
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" | tee "$(basename "$OUT").sha256" )
echo "payload: $(du -h "$OUT" | cut -f1), version $VERSION"
