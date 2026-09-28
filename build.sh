#!/bin/sh
# builds a universal, ad-hoc signed furrpc.app into ./build
set -e
cd "$(dirname "$0")"
app=build/furrpc.app
rm -rf build
mkdir -p $app/Contents/MacOS $app/Contents/Resources
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos13.0 src/main.swift -framework IOKit -o build/furrpc-$arch
done
lipo -create build/furrpc-arm64 build/furrpc-x86_64 -output $app/Contents/MacOS/furrpc
rm build/furrpc-arm64 build/furrpc-x86_64
cp src/Info.plist $app/Contents/
cp games.json $app/Contents/Resources/
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
# the github icon is fetched here, once, while building. the app itself never downloads anything
if ! curl -fsSL --retry 2 -m 30 -o $app/Contents/Resources/github.png https://cdn-icons-png.flaticon.com/256/25/25231.png; then
  rm -f $app/Contents/Resources/github.png
  echo "warning: could not fetch the github icon, the link will show text only"
fi
codesign --force --deep -s - $app
echo "built $app"
