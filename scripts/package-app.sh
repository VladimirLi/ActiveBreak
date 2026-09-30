#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/release-config.sh"
BUILD_DIR="$ROOT/.build"
MODULE_CACHE="$BUILD_DIR/module-cache"

# ARCHS="arm64 x86_64" builds each slice separately and merges them with lipo
# (no Xcode-only multi-arch support needed); default is the host architecture.
swift_build() {
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --package-path "$ROOT" -c release --disable-sandbox "$@"
}

mkdir -p "$MODULE_CACHE"
BINARY="$BUILD_DIR/$EXECUTABLE_NAME.universal"
if [ -n "${ARCHS:-}" ]; then
    SLICES=""
    for arch in $ARCHS; do
        swift_build --triple "$arch-apple-macosx$MIN_MACOS"
        slice_dir=$(swift_build --triple "$arch-apple-macosx$MIN_MACOS" --show-bin-path)
        SLICES="$SLICES $slice_dir/$EXECUTABLE_NAME"
    done
    # shellcheck disable=SC2086
    lipo -create $SLICES -output "$BINARY"
else
    swift_build
    cp "$(swift_build --show-bin-path)/$EXECUTABLE_NAME" "$BINARY"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
rm -f "$BINARY"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$BUNDLE_SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
"$ROOT/scripts/verify-app.sh" "$APP"
printf '%s\n' "$APP"
