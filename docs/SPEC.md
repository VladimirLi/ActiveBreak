# ActiveBreak normative specification

## Platform and privacy

ActiveBreak MUST run on macOS 14 or newer as a menu-bar-only app with no normal
Dock presence. It MUST use aggregate HID idle time, poll approximately once per
second, treat all HID input equally, and MUST NOT request Accessibility or Input
Monitoring permission or capture raw input.

## Timer model

The default work threshold is 25 minutes. The default dead time is 5 minutes.
Both are configurable and MUST be captured when an interval starts; later
changes apply only to the next interval.

The first activity while idle MUST start an interval silently. Time after the
last activity is provisional work:

- Activity strictly before dead time validates the entire gap as work.
- Reaching dead time reclassifies the entire unresolved gap as break time,
  closes and logs the interval, and returns to idle.
- The displayed countdown MUST include provisional time and MAY jump back when
  dead time is reached.

Remaining time below one hour MUST use `MM:SS`. One hour or more MUST use hours
and minutes. At zero, exactly one threshold event MUST occur. Notification and
sound MUST be independently configurable and default on. Overtime MUST continue
indefinitely with a conspicuous urgent menu-bar presentation.

## Controls and lifecycle

The menu MUST contain only Pause/Resume, Settings, Dashboard, and Quit.

Pause MUST immediately log the interval using validated work only, discard the
unresolved provisional gap, and enter paused state. Resume MUST enter idle and
wait for activity.

State MUST persist across termination and restart. Relaunch downtime shorter
than the interval's captured dead time MUST preserve state without counting
app-off wall time as work. Downtime equal to or longer than dead time MUST count
as a break and clear the interval. Sleep or reboot while the app is closed MUST
also count as a break and clear active state. Sleep while running MUST clear
state on wake. Lock MUST follow the ordinary dead-time rule.

Launch at login MUST default on and use `SMAppService`. Failures MUST be shown
without damaging timer or history state.

## History and reporting

History MUST remain until one confirmed Delete All History action. Each record
MUST include absolute interval start/end timestamps, validated active duration,
overtime, break duration, and exact validated work segments with their
regular/overtime classification. Pause-closed intervals MUST be retained.

Intervals and breaks MUST be split at local midnight for aggregation. Stored
timestamps remain absolute and MUST be regrouped using the current local
timezone.

Dashboard MUST provide daily, weekly, and monthly summaries of active time,
overtime, break count, and average interval. CSV and JSON export MUST use an
selected calendar-day range, ending exclusively at the next local midnight,
and a native save panel. Exported records MUST be
clipped to that range and split at current-local-midnight boundaries; exported
timestamps and durations MUST NOT extend outside the selected range.

## Distribution

The project MUST build and test with Swift Package Manager and Command Line
Tools. `scripts/package-app.sh` MUST produce an unsigned `ActiveBreak.app`
containing an executable and an `Info.plist` with `LSUIElement` enabled.
