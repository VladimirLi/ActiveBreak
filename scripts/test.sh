#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
MODULE_CACHE="$BUILD_DIR/module-cache"
RUNNER_SOURCE="${TMPDIR:-/tmp}/activebreak-test-main.swift"
RUNNER="${TMPDIR:-/tmp}/activebreak-test-runner"

mkdir -p "$MODULE_CACHE"
trap 'rm -f "$RUNNER_SOURCE" "$RUNNER"' EXIT INT TERM
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift test --package-path "$ROOT" --disable-sandbox

BIN_DIR=$(CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --package-path "$ROOT" --show-bin-path --disable-sandbox)

cat > "$RUNNER_SOURCE" <<'SWIFT'
import Testing

@main
struct ActiveBreakTestRunner {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
SWIFT

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc -parse-as-library \
    "$RUNNER_SOURCE" \
    "$BIN_DIR"/ActiveBreakCore.build/*.swift.o \
    "$BIN_DIR"/ActiveBreakCoreTests.build/*.swift.o \
    -F /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
    -plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
    -framework Testing \
    -Xlinker -rpath \
    -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
    -Xlinker -rpath \
    -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
    -o "$RUNNER"

"$RUNNER"
