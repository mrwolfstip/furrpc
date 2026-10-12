#!/bin/sh
# builds a universal, ad-hoc signed furrpc.app into ./build
set -e
cd "$(dirname "$0")"
rm -rf build
mkdir -p build
# Sign outside Desktop/iCloud so Finder cannot race codesign by attaching metadata.
stagedir=$(mktemp -d "${TMPDIR:-/tmp}/furrpc-build.XXXXXX")
trap 'rm -rf "$stagedir"' EXIT
app=$stagedir/furrpc.app
out=build/furrpc.app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos13.0 src/main.swift -framework IOKit -o build/furrpc-$arch
done
lipo -create build/furrpc-arm64 build/furrpc-x86_64 -output $app/Contents/MacOS/furrpc
rm build/furrpc-arm64 build/furrpc-x86_64
cp src/Info.plist $app/Contents/
cp games.json $app/Contents/Resources/
cp bot/furrbot.py $app/Contents/Resources/
cp -R browser-extension $app/Contents/Resources/
cp furrpc.png $app/Contents/Resources/
# app icon: furrpc.png is resized into an iconset and turned into AppIcon.icns (sips and iconutil ship with macos)
iconset=build/AppIcon.iconset
mkdir -p $iconset
for size in 16 32 128 256 512; do
  sips -z $size $size furrpc.png --out $iconset/icon_${size}x${size}.png >/dev/null
  sips -z $((size * 2)) $((size * 2)) furrpc.png --out $iconset/icon_${size}x${size}@2x.png >/dev/null
done
iconutil -c icns $iconset -o $app/Contents/Resources/AppIcon.icns
rm -rf $iconset
[ -f menubar.png ] && cp menubar.png $app/Contents/Resources/
# the github icon is fetched here, once, while building. the app itself only fetches tvmaze data, and only when apple tv lookups are on
if ! curl -fsSL --retry 2 -m 30 -o $app/Contents/Resources/github.png https://cdn-icons-png.flaticon.com/256/25/25231.png; then
  rm -f $app/Contents/Resources/github.png
  echo "warning: could not fetch the github icon, the link will show text only"
fi
# Finder/download metadata copied from local source files makes codesign reject the bundle.
# Strip it from the build product only; the source files are left untouched.
xattr -cr $app
codesign --force --deep -s - $app
codesign --verify --deep --strict $app
# Copy without resource forks into the requested output location.
ditto --norsrc $app $out
xattr -cr $out

# Store-submission packages. Browsers sign these after review; local packages cannot
# be silently installed on macOS. manifest.json must be at the root of each archive.
extbuild=build/extensions
mkdir -p $extbuild/chromium $extbuild/firefox
cp browser-extension/background.js browser-extension/content.js browser-extension/sources.js browser-extension/popup.html browser-extension/popup.css browser-extension/popup.js $extbuild/chromium/
cp browser-extension/background.js browser-extension/content.js browser-extension/sources.js browser-extension/popup.html browser-extension/popup.css browser-extension/popup.js $extbuild/firefox/
cp -R browser-extension/icons $extbuild/chromium/
cp -R browser-extension/icons $extbuild/firefox/
cp browser-extension/manifest-chromium.json $extbuild/chromium/manifest.json
cp browser-extension/manifest-firefox.json $extbuild/firefox/manifest.json
(cd $extbuild/chromium && /usr/bin/zip -qr ../furrpc-chromium-store.zip .)
(cd $extbuild/firefox && /usr/bin/zip -qr ../furrpc-firefox-amo.zip .)
# Clear any metadata attached by Finder/file providers while the remaining build ran.
xattr -cr $out
echo "built $out"
echo "built $extbuild/furrpc-chromium-store.zip"
echo "built $extbuild/furrpc-firefox-amo.zip"
