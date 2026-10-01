#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/release-config.sh"
APP=${1:-$APP}
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"

test -d "$APP"
test -x "$EXECUTABLE"
plutil -lint "$PLIST"
test "$(plutil -extract CFBundleExecutable raw -o - "$PLIST")" = "$EXECUTABLE_NAME"
test "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" = "$BUNDLE_ID"
test "$(plutil -extract CFBundleIconFile raw -o - "$PLIST")" = "AppIcon"
test -s "$APP/Contents/Resources/AppIcon.icns"
test -s "$APP/Contents/Resources/MenuBarGlyphTemplate.png"
test -s "$APP/Contents/Resources/MenuBarGlyphTemplate@2x.png"
test "$(plutil -extract LSUIElement raw -o - "$PLIST")" = "true"
codesign --verify --deep --strict "$APP"
printf 'Valid app bundle: %s\n' "$APP"
