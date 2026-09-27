#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
OUT="$ROOT/../../outputs/Retina Dummy.app"
STAGE="$(mktemp -d)/Retina Dummy.app"
trap 'rm -rf "${STAGE:h}"' EXIT
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

VERSION="${VERSION:-0.7.1}"
BUILD_NUMBER="${BUILD_NUMBER:-10}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

clang -Wall -Wextra -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework Cocoa -framework CoreGraphics -framework ServiceManagement \
  "$ROOT/main.m" -o "$STAGE/Contents/MacOS/RetinaDummy"
cp "$ROOT/Info.plist" "$STAGE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$STAGE/Contents/Info.plist"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$STAGE"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$STAGE"
fi
codesign --verify --deep --strict --verbose=2 "$STAGE"
plutil -lint "$STAGE/Contents/Info.plist"
rm -rf "$OUT" "$ROOT/../../outputs/Retina-Dummy.zip"
ditto "$STAGE" "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ROOT/../../outputs/Retina-Dummy.zip"
echo "$OUT"
