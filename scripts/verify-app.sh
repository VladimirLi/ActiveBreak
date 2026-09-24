#!/bin/sh
set -eu

APP=${1:-"$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)/.build/ActiveBreak.app"}
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/ActiveBreak"

test -d "$APP"
test -x "$EXECUTABLE"
plutil -lint "$PLIST"
test "$(plutil -extract CFBundleExecutable raw -o - "$PLIST")" = "ActiveBreak"
test "$(plutil -extract LSUIElement raw -o - "$PLIST")" = "true"
codesign --verify --deep --strict "$APP"
printf 'Valid unsigned app bundle: %s\n' "$APP"
