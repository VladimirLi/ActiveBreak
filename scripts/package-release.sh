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
DMG_BACKGROUND="$ROOT/docs/brand/dmg-background.tiff"
DMG_SETTINGS="$ROOT/docs/brand/tools/dmg-settings.py"

if ! command -v dmgbuild >/dev/null 2>&1; then
    printf 'dmgbuild not found. Install it with:\n  python3 -m pip install --require-hashes -r scripts/dmgbuild-requirements.txt\n' >&2
    exit 1
fi

rm -rf "$DIST"
mkdir -p "$DIST"

# ditto keeps the code signature, symlinks and permissions intact.
ditto -c -k --keepParent "$APP" "$ZIP"

# dmgbuild writes the window layout and background without needing Finder.
dmgbuild -s "$DMG_SETTINGS" -D app="$APP" -D background="$DMG_BACKGROUND" "$APP_NAME" "$DMG"
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
hdiutil verify "$DMG"

(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
cat "$DIST/SHA256SUMS.txt"
