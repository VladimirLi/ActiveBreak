#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/.build/ActiveBreak.app"

"$ROOT/scripts/verify-app.sh" "$APP"

open -n -W --env ACTIVEBREAK_DISABLE_LOGIN_ITEM_MUTATION=1 "$APP" &
launcher=$!
sleep 5
kill -0 "$launcher"
pkill -x ActiveBreak
wait "$launcher" 2>/dev/null || true
printf 'ActiveBreak remained running for 5 seconds with login-item mutation disabled.\n'
