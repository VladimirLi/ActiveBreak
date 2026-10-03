#!/bin/sh
# Builds the app (scripts/package-app.sh) and produces, in ./dist:
#   <prefix>-<version>.dmg, <prefix>-<version>.zip, SHA256SUMS.txt
# Environment: VERSION, SIGN_IDENTITY, ARCHS, BUILD_NUMBER (see release-config.sh).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/release-config.sh"

"$ROOT/scripts/package-app.sh"

PLIST="$APP/Contents/Info.plist"
test "$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" = "$BUNDLE_SHORT_VERSION"
test "$(plutil -extract CFBundleVersion raw -o - "$PLIST")" = "$BUILD_NUMBER"

NAME="$ARTIFACT_PREFIX-$VERSION"
DMG="$DIST/$NAME.dmg"
ZIP="$DIST/$NAME.zip"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/stillbreak-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM

rm -rf "$DIST"
mkdir -p "$DIST"

# ditto keeps the code signature, symlinks and permissions intact.
ditto -c -k --keepParent "$APP" "$ZIP"

ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
hdiutil verify "$DMG"

(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
cat "$DIST/SHA256SUMS.txt"
