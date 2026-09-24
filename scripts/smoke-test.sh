#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/.build/ActiveBreak.app"
STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/activebreak-smoke.XXXXXX")
STATE_FILE="$STATE_DIR/state.json"
REAL_STATE="$HOME/Library/Application Support/ActiveBreak/state.json"
launched_pid=

"$ROOT/scripts/verify-app.sh" "$APP"

fingerprint() {
    if [ -f "$1" ]; then
        cksum < "$1"
    else
        printf 'absent\n'
    fi
}

before=$(fingerprint "$REAL_STATE")
cleanup() {
    if [ -n "$launched_pid" ]; then
        kill "$launched_pid" 2>/dev/null || true
        wait "$launched_pid" 2>/dev/null || true
    fi
    rm -f "$STATE_FILE"
    rmdir "$STATE_DIR"
}
trap cleanup EXIT INT TERM

ACTIVEBREAK_DISABLE_LOGIN_ITEM_MUTATION=1 \
ACTIVEBREAK_STATE_FILE="$STATE_FILE" \
"$APP/Contents/MacOS/ActiveBreak" &
launched_pid=$!
sleep 5
kill -0 "$launched_pid"
test -f "$STATE_FILE"
test "$(fingerprint "$REAL_STATE")" = "$before"
kill "$launched_pid"
wait "$launched_pid" 2>/dev/null || true
launched_pid=
printf 'ActiveBreak remained running for 5 seconds with login-item mutation disabled.\n'
