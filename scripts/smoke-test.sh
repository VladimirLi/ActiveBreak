#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/.build/ActiveBreak.app"
STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/activebreak-smoke.XXXXXX")
STATE_FILE="$STATE_DIR/state.json"
REAL_STATE="$HOME/Library/Application Support/ActiveBreak/state.json"
REPORT_DIR="$HOME/Library/Logs/DiagnosticReports"

"$ROOT/scripts/verify-app.sh" "$APP"
BIN_DIR=$(CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache" \
    swift build --package-path "$ROOT" -c release --show-bin-path --disable-sandbox)
SMOKE="$BIN_DIR/ActiveBreakSmoke"
test -x "$SMOKE"

fingerprint() {
    if [ -f "$1" ]; then
        shasum -a 256 "$1"
    else
        printf 'absent\n'
    fi
}

before=$(fingerprint "$REAL_STATE")
reports_before="$STATE_DIR/reports-before.txt"
reports_after="$STATE_DIR/reports-after.txt"
if [ -d "$REPORT_DIR" ]; then
    find "$REPORT_DIR" -maxdepth 1 -name 'ActiveBreak*.ips' -exec stat -f '%N %z %m' {} \; \
        | sort > "$reports_before"
else
    : > "$reports_before"
fi
cleanup() {
    rm -rf "$STATE_DIR"
}
trap cleanup EXIT INT TERM

ACTIVEBREAK_STATE_FILE="$STATE_FILE" \
"$SMOKE" --iterations 300
test -f "$STATE_FILE"
test "$(fingerprint "$REAL_STATE")" = "$before"
if [ -d "$REPORT_DIR" ]; then
    find "$REPORT_DIR" -maxdepth 1 -name 'ActiveBreak*.ips' -exec stat -f '%N %z %m' {} \; \
        | sort > "$reports_after"
else
    : > "$reports_after"
fi
cmp "$reports_before" "$reports_after"
printf 'ActiveBreak core smoke exited cleanly with isolated state and no crash report.\n'
