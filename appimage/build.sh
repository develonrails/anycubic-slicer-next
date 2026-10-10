#!/usr/bin/env bash
# Build the AppImage from Anycubic's .deb. Used by the release workflow; see
# HOWTO.md for what each step is for.
#
#   appimage/build.sh <anycubicslicernext.deb> [output-dir]
#
# Writes AnycubicSlicer-<version>-x86_64.AppImage and its .zsync to output-dir
# (default: the current directory) and prints the AppImage's path.
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { echo "usage: $0 <anycubicslicernext.deb> [output-dir]" >&2; exit 1; }

deb=$(realpath "$1")
out=$(realpath "${2:-.}")
here=$(dirname "$(realpath "$0")")

# The maintained appimagetool, not the one from AppImage/AppImageKit: that one
# is obsolete and embeds a runtime that needs libfuse.so.2, which distributions
# such as Debian testing no longer ship (issue #11).
#
# The tool is pinned by hash. The runtime it embeds is fetched separately from
# type2-runtime's rolling `continuous` release and checked against the
# AppImage project's signing key instead: it receives fixes there, and pinning
# its hash would break every build the next time it does.
APPIMAGETOOL_URL=https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_URL=https://github.com/AppImage/type2-runtime/releases/download/continuous
RUNTIME_KEY=570C77ACEA40C0F1B758902CBF96CCA56490F695

# Embedded in the AppImage so AppImageUpdate and Gear Lever can update it from
# the latest GitHub release, downloading only the parts that changed.
UPDATE_INFO='gh-releases-zsync|develonrails|anycubic-slicer-next|latest|AnycubicSlicer-*-x86_64.AppImage.zsync'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

# Extract the deb (tar picks the compression from the file)
ar x "$deb"
mkdir extracted
tar xf data.tar.* -C extracted
version=$(tr -d '[:space:]' < extracted/usr/share/AnycubicSlicerNext/resources/build-version.txt)
[[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || { echo "unexpected app version '$version'" >&2; exit 1; }

# AppDir. Resources go to the root as well: the app looks for them relative to
# where it runs from (HOWTO.md, "Resources Location").
app=AnycubicSlicer.AppDir
mkdir "$app"
cp -r extracted/usr/* "$app"/
rm -rf "$app/include" "$app/lib/cmake"
find "$app/lib" -maxdepth 1 -name '*.a' -delete
cp -r "$app/share/AnycubicSlicerNext/resources" "$app"/
cp "$app/share/AnycubicSlicerNext/resources/images/AnycubicSlicer.png" "$app"/
cp "$here/AnycubicSlicer.desktop" "$app"/
install -m755 "$here/AppRun" "$app/AppRun"

# Tools
curl -fsSL --retry 3 -o appimagetool "$APPIMAGETOOL_URL"
echo "$APPIMAGETOOL_SHA256  appimagetool" | sha256sum -c --quiet -
chmod +x appimagetool

curl -fsSL --retry 3 -o runtime "$RUNTIME_URL/runtime-x86_64"
curl -fsSL --retry 3 -o runtime.sig "$RUNTIME_URL/runtime-x86_64.sig"
curl -fsSL --retry 3 -o runtime-key.asc "$RUNTIME_URL/signing-pubkey.asc"
# gpgv rather than gpg: it needs no agent and no keyring of the user's.
# VALIDSIG's last field is the primary key's fingerprint, so a good signature
# from any key other than the AppImage project's does not count.
gpg --dearmor < runtime-key.asc > runtime-key.gpg
gpgv --homedir "$work" --keyring "$work/runtime-key.gpg" --status-fd 1 runtime.sig runtime 2>/dev/null |
  grep -q "^\[GNUPG:\] VALIDSIG .* $RUNTIME_KEY\$" ||
  { echo "type2-runtime signature does not verify against $RUNTIME_KEY" >&2; exit 1; }

# Build. APPIMAGE_EXTRACT_AND_RUN lets appimagetool (itself an AppImage) run
# without FUSE, as on CI runners and in containers.
appimage=$out/AnycubicSlicer-$version-x86_64.AppImage
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 ./appimagetool --no-appstream \
  --runtime-file runtime --updateinformation "$UPDATE_INFO" \
  "$app" "$appimage" >&2

# appimagetool writes the .zsync to the working directory
mv ./*.zsync "$out"/

echo "$appimage"
