#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUTS="$ROOT/../../outputs"
APP="$OUTPUTS/Retina Dummy.app"
DMG="$OUTPUTS/Retina-Dummy-${VERSION:-0.7.1}.dmg"

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  echo "SIGNING_IDENTITY is required for a public release." >&2
  exit 1
fi

SIGNING_IDENTITY="$SIGNING_IDENTITY" VERSION="${VERSION:-0.7.1}" BUILD_NUMBER="${BUILD_NUMBER:-10}" "$ROOT/build.sh"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$APP" "$staging/Retina Dummy.app"
ln -s /Applications "$staging/Applications"
rm -f "$DMG"
hdiutil create -volname "Retina Dummy" -srcfolder "$staging" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "NOTARY_PROFILE is not set; skipping Apple notarization."
fi

spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
echo "$DMG"
