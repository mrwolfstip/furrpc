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
[ -f menubar.png ] && cp menubar.png $app/Contents/Resources/
codesign --force --deep -s - $app
echo "built $app"
