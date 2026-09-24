# ActiveBreak

ActiveBreak is a native, menu-bar-only macOS utility that reminds you to take
breaks based on actual keyboard, mouse, scroll, or tablet activity. Its current
countdown is shown directly in the menu bar.

It uses macOS's aggregate HID idle-time API. It does not record keys, pointer
positions, app names, window titles, or raw input events, and it does not need
Accessibility or Input Monitoring permission.

## How timing works

The default work threshold is 25 minutes and the default dead time is 5
minutes. Both are configurable. Setting changes apply to the next interval.

ActiveBreak uses a provisional "Model A" timeline:

```text
activity ----- provisional work gap ----- activity
0:00                                      4:59
```

If activity returns strictly before 5:00, the whole 4:59 gap remains work. If
no activity returns and the gap reaches 5:00, ActiveBreak retroactively removes
that unresolved gap from active time, records it as a break, closes the
interval, and returns to idle. The menu countdown can therefore jump back when
dead time is reached.

The permissionless aggregate HID API exposes only the latest event seen at each
one-second poll. If that event is first observed no more than one polling
interval after the dead-time boundary, ActiveBreak conservatively counts the
gap as work because an earlier event may have occurred between polls. Events
later than that one-second grace close the old interval normally.

At zero, ActiveBreak sends one notification. Notification banners and sound can
be disabled independently. The timer continues below zero until dead time,
Pause, sleep (including while the app is closed), reboot, or a sufficiently
long app shutdown closes the interval.

Pause closes the current interval using validated work only. Resume waits for
new activity. History is retained locally until **Delete All History** is
confirmed. Each interval has one stable identifier, and applying the same
closure more than once cannot create a second history record.

## Requirements

- macOS 14 or newer
- Swift 6.3 or newer
- Command Line Tools or Xcode

## Build and test

With Command Line Tools:

```sh
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox

# Swift 6.3.3 CLT workaround that also executes the registered test bundle:
./scripts/test.sh

CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift build -c release --disable-sandbox

./scripts/package-app.sh
./scripts/smoke-test.sh
```

The cache variables and `--disable-sandbox` are needed only in restricted
shells. In a normal terminal, `swift test` and `swift build -c release` are
sufficient.

With Xcode, open `Package.swift`, select the `ActiveBreak` executable scheme,
and Run. Use Product > Test to run the package tests. To create the standalone
unsigned bundle, run `./scripts/package-app.sh` in Terminal.

## Dashboard and exports

Dashboard provides daily, weekly, and monthly summaries for active time,
overtime, break count, and average interval. CSV and JSON exports use the
selected calendar-day range, represented as a half-open interval ending at
the next local midnight. Absolute timestamps are stored; grouping is
recomputed in the Mac's current local timezone. Export rows are clipped to the
selected range and split at local midnight. JSON records include exact
`workSegments`, each marked as regular or overtime.

CSV columns are:

```text
id,interval_start,interval_end,active_seconds,overtime_seconds,break_start,break_end,break_seconds
```

JSON is an array of records with `id`, `intervalStart`, `intervalEnd`,
`activeDuration`, `overtimeDuration`, `breakStart`, `breakEnd`,
`breakDuration`, and `workSegments`. Older state files without timeline
segments are decoded into the closest equivalent contiguous timeline.

## Data and privacy

All settings, timer state, and history are stored as JSON in:

```text
~/Library/Application Support/ActiveBreak/state.json
```

There is no network service, telemetry, account, cloud sync, or app-level
tracking.

ActiveBreak writes bounded local diagnostics to Apple's unified log under the
`com.vladimirli.ActiveBreak` subsystem, with `timer`, `lifecycle`,
`persistence`, and `login-item` categories:

```sh
log show --last 1h --predicate 'subsystem == "com.vladimirli.ActiveBreak"'
```

Diagnostics include timing decisions, state transitions, effect kinds,
persistence outcomes, lifecycle handling, and login-item outcomes. They never
include keys, pointer coordinates, app names, window titles, screenshots, or
raw input events.

State is saved when it changes, at lifecycle boundaries, and at most every 60
seconds as a checkpoint. An abrupt process loss can therefore lose at most the
current provisional interval since the latest checkpoint.

The smoke script runs the non-GUI `ActiveBreakSmoke` executable with an
isolated `ACTIVEBREAK_STATE_FILE`, exits normally, verifies that live state is
unchanged, and fails if an `ActiveBreak` crash report was added or modified.

## History repair

Build the tools, then preview a state file without modifying it:

```sh
swift build -c release --disable-sandbox
.build/release/ActiveBreakRepair \
  --state "$HOME/Library/Application Support/ActiveBreak/state.json" \
  --manifest .build/history-repair-preview.json
```

Add `--candidate .build/repaired-state.json` to write a separate repaired copy
for review or a second idempotency preview. `--apply` is deliberately explicit:
it creates a timestamped backup beside the original, atomically replaces the
state, and validates the result. State, candidate, and manifest paths must not
refer to the same file through direct, normalized, symbolic-link, or hard-link
paths. Keep the backup until the repaired history has been reviewed.

## Architecture

- `ActiveBreakCore`: pure reducer, persistence, aggregation, and export logic
- `ActiveBreak`: SwiftUI menu bar, settings, dashboard, notifications, and
  `SMAppService` integration
- `ActiveBreakRepair`: preview/apply history repair command
- `ActiveBreakSmoke`: isolated non-GUI persistence and lifecycle harness
- `scripts/package-app.sh`: release build and unsigned `.app` assembly

The normative behavior is in [`docs/SPEC.md`](docs/SPEC.md).

## Limitations

- The packaged app uses only a local ad-hoc signature and is not Developer ID
  signed or notarized.
- Launch at login can fail for an unsigned or translocated bundle; the Settings
  window reports the macOS error without changing the timer.
- macOS controls whether notification banners and menu-bar text colors are
  shown exactly as requested.
- History is a local JSON file with no sync. Repair apply mode creates a local
  timestamped backup, but ordinary saves do not.

## License

MIT. See [LICENSE](LICENSE).
