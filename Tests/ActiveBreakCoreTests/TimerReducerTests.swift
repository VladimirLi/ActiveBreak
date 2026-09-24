import Foundation
import Testing
@testable import ActiveBreakCore

private let settings = BreakSettings(workThreshold: 10, deadTime: 300)
private let start = Date(timeIntervalSince1970: 1_700_000_000)

@Test func firstActivityStartsSilently() {
    var reducer = TimerReducer()
    #expect(reducer.activity(at: start, settings: settings) == [])
    #expect(reducer.state.mode == .active)
    #expect(reducer.state.interval?.settings == settings)
}

@Test func activityAtFourMinutesFiftyNineSecondsValidatesWholeGap() {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    #expect(reducer.activity(at: start.addingTimeInterval(299), settings: settings) == [.notify(sound: true)])
    #expect(reducer.state.interval?.validatedActive == 299)
}

@Test func inactivityAtFiveMinutesReclassifiesWholeGapAsBreak() throws {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    let record = try #require(loggedRecord(from: reducer.sample(at: start.addingTimeInterval(300))))
    #expect(reducer.state.mode == .idle)
    #expect(record.activeDuration == 0)
    #expect(record.breakDuration == 300)
}

@Test func provisionalCountdownRollsBackAfterDeadTime() {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    #expect(reducer.remaining(at: start.addingTimeInterval(299), defaultSettings: settings) == -289)
    reducer.sample(at: start.addingTimeInterval(300))
    #expect(reducer.remaining(at: start.addingTimeInterval(300), defaultSettings: settings) == 10)
}

@Test func thresholdNotifiesOnceAndOvertimeContinues() {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    #expect(reducer.sample(at: start.addingTimeInterval(10)) == [.notify(sound: true)])
    #expect(reducer.sample(at: start.addingTimeInterval(120)) == [])
    #expect(reducer.remaining(at: start.addingTimeInterval(120), defaultSettings: settings) == -110)
}

@Test func deadTimeClosesOvertimeAndReturnsIdle() throws {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    reducer.activity(at: start.addingTimeInterval(20), settings: settings)
    let record = try #require(loggedRecord(from: reducer.sample(at: start.addingTimeInterval(320))))
    #expect(record.activeDuration == 20)
    #expect(record.overtimeDuration == 10)
    #expect(reducer.state.mode == .idle)
}

@Test func pauseLogsValidatedWorkOnlyAndResumeWaitsForActivity() throws {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    reducer.activity(at: start.addingTimeInterval(8), settings: settings)
    let record = try #require(loggedRecord(from: reducer.pause(at: start.addingTimeInterval(100))))
    #expect(record.activeDuration == 8)
    #expect(record.breakDuration == 0)
    #expect(reducer.state.mode == .paused)
    reducer.resume()
    #expect(reducer.state.mode == .idle)
    #expect(reducer.state.interval == nil)
}

@Test func shortRelaunchPreservesStateWithoutCountingDowntime() {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    reducer.activity(at: start.addingTimeInterval(5), settings: settings)
    reducer.restore(savedAt: start.addingTimeInterval(6), now: start.addingTimeInterval(106))
    reducer.activity(at: start.addingTimeInterval(110), settings: settings)
    #expect(reducer.state.interval?.validatedActive == 10)
}

@Test func relaunchUsesTotalUnresolvedGapForDeadTime() throws {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    let effects = reducer.restore(
        savedAt: start.addingTimeInterval(299),
        now: start.addingTimeInterval(301)
    )
    let record = try #require(loggedRecord(from: effects))

    #expect(record.activeDuration == 0)
    #expect(record.breakDuration == 301)
    #expect(reducer.state.mode == .idle)
}

@Test func persistedFractionalRelaunchGapStaysBelowDeadTime() throws {
    let fractionalStart = Date(timeIntervalSince1970: 1_700_000_000.9)
    let persisted = PersistedData(
        settings: settings,
        timer: TimerState(
            mode: .active,
            interval: ActiveInterval(
                startedAt: fractionalStart,
                lastActivityAt: fractionalStart,
                settings: settings
            )
        ),
        savedAt: fractionalStart.addingTimeInterval(250)
    )
    let decoded = try JSONDecoder.activeBreak.decode(
        PersistedData.self,
        from: JSONEncoder.activeBreak.encode(persisted)
    )
    var reducer = TimerReducer(state: decoded.timer)

    #expect(reducer.restore(
        savedAt: decoded.savedAt,
        now: fractionalStart.addingTimeInterval(299.9)
    ).isEmpty)
    #expect(reducer.state.mode == .active)
}

@Test func shortTotalRelaunchGapExcludesOnlyAppOffTime() {
    var reducer = TimerReducer()
    let longThreshold = BreakSettings(workThreshold: 1_000, deadTime: 300)
    reducer.activity(at: start, settings: longThreshold)
    reducer.restore(
        savedAt: start.addingTimeInterval(100),
        now: start.addingTimeInterval(102)
    )
    reducer.activity(at: start.addingTimeInterval(200), settings: longThreshold)

    #expect(reducer.state.interval?.validatedActive == 198)
    #expect(reducer.state.interval?.workSegments == [
        TimeSegment(start: start, end: start.addingTimeInterval(100)),
        TimeSegment(start: start.addingTimeInterval(102), end: start.addingTimeInterval(200)),
    ])
}

@Test func longRelaunchCountsAsBreakAndClearsState() throws {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    reducer.activity(at: start.addingTimeInterval(5), settings: settings)
    let effects = reducer.restore(savedAt: start.addingTimeInterval(6), now: start.addingTimeInterval(306))
    let record = try #require(loggedRecord(from: effects))
    #expect(record.activeDuration == 5)
    #expect(record.breakDuration == 301)
    #expect(reducer.state.mode == .idle)
}

@Test func wakeAlwaysClearsActiveState() throws {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    reducer.activity(at: start.addingTimeInterval(5), settings: settings)
    let record = try #require(loggedRecord(from: reducer.wake(at: start.addingTimeInterval(20))))
    #expect(record.activeDuration == 5)
    #expect(record.breakDuration == 15)
    #expect(reducer.state.mode == .idle)
}

@Test func activeIntervalKeepsCapturedSettings() {
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: settings)
    let changed = BreakSettings(workThreshold: 60, deadTime: 30)
    reducer.activity(at: start.addingTimeInterval(20), settings: changed)
    #expect(reducer.state.interval?.settings == settings)
    #expect(reducer.remaining(at: start.addingTimeInterval(20), defaultSettings: changed) == -10)
}

@Test func notificationAndSoundCanBeDisabledIndependently() {
    var soundOnly = TimerReducer()
    soundOnly.activity(
        at: start,
        settings: BreakSettings(workThreshold: 1, deadTime: 10, notificationsEnabled: false)
    )
    #expect(soundOnly.sample(at: start.addingTimeInterval(1)) == [.playSound])

    var silentNotification = TimerReducer()
    silentNotification.activity(
        at: start,
        settings: BreakSettings(workThreshold: 1, deadTime: 10, soundEnabled: false)
    )
    #expect(silentNotification.sample(at: start.addingTimeInterval(1)) == [.notify(sound: false)])
}

private func loggedRecord(from effects: [TimerEffect]) -> HistoryRecord? {
    for effect in effects {
        if case let .log(record) = effect { return record }
    }
    return nil
}
