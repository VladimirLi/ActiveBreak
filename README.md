# ActiveBreak

ActiveBreak is a native, menu-bar-only macOS utility that reminds you to take
breaks based on actual keyboard, mouse, scroll, or tablet activity.

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

At zero, ActiveBreak sends one notification. Notification banners and sound can
be disabled independently. The timer continues below zero until dead time,
Pause, sleep, or a sufficiently long app shutdown closes the interval.

Pause closes the current interval using validated work only. Resume waits for
new activity. History is retained locally until **Delete All History** is
confirmed.

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
selected inclusive date range. Absolute timestamps are stored; grouping is
recomputed in the Mac's current local timezone.

## Data and privacy

All settings, timer state, and history are stored as JSON in:

```text
~/Library/Application Support/ActiveBreak/state.json
```

There is no network service, telemetry, account, cloud sync, or app-level
tracking.

## Architecture

- `ActiveBreakCore`: pure reducer, persistence, aggregation, and export logic
- `ActiveBreak`: SwiftUI menu bar, settings, dashboard, notifications, and
  `SMAppService` integration
- `scripts/package-app.sh`: release build and unsigned `.app` assembly

The normative behavior is in [`docs/SPEC.md`](docs/SPEC.md).

## Limitations

- The packaged app uses only a local ad-hoc signature and is not Developer ID
  signed or notarized.
- Launch at login can fail for an unsigned or translocated bundle; the Settings
  window reports the macOS error without changing the timer.
- macOS controls whether notification banners and menu-bar text colors are
  shown exactly as requested.
- History is a local JSON file with no backup or sync.

## License

MIT. See [LICENSE](LICENSE).
