import Foundation
import Testing
@testable import ActiveBreakCore

@Test func timerDiagnosticContainsBoundedDecisionFields() throws {
    let inferred = Date(timeIntervalSince1970: 1_700_000_000.125)
    let recordID = UUID()
    let event = DiagnosticEvent(
        category: .timer,
        event: "sample",
        reason: "dead-time",
        stateBefore: .active,
        stateAfter: .idle,
        idleSeconds: 300.25,
        inferredEventAt: inferred,
        threshold: 1_500,
        deadTime: 300,
        validated: 42,
        provisional: 0,
        overtime: 0,
        effectKinds: ["history"],
        recordID: recordID,
        outcome: "closed"
    )

    let fields = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder.activeBreak.encode(event))
            as? [String: Any]
    )
    #expect(Set(fields.keys) == [
        "category", "event", "reason", "stateBefore", "stateAfter",
        "idleSeconds", "inferredEventAt", "threshold", "deadTime",
        "validated", "provisional", "overtime", "effectKinds",
        "recordID", "outcome",
    ])
    #expect(fields["recordID"] as? String == recordID.uuidString)
    #expect(fields["inferredEventAt"] != nil)
    #expect(fields.keys.allSatisfy {
        !["key", "keystroke", "pointer", "coordinates", "appName", "windowTitle"].contains($0)
    })
}

@Test func pureDeadTimeDiagnosticUsesClosedIntervalAndRecord() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let intervalID = UUID()
    let settings = BreakSettings(workThreshold: 120, deadTime: 300)
    let interval = ActiveInterval(
        id: intervalID,
        startedAt: start,
        lastActivityAt: start.addingTimeInterval(40),
        workSegments: [TimeSegment(start: start, end: start.addingTimeInterval(40))],
        settings: settings
    )
    var reducer = TimerReducer(state: TimerState(mode: .active, interval: interval))
    var detector = IdleActivityDetector()
    detector.baseline(at: interval.lastActivityAt)
    let now = interval.lastActivityAt.addingTimeInterval(300)

    let sample = PermissionlessHIDPolicy.processSample(
        now: now,
        idleSeconds: 300,
        detector: &detector,
        reducer: &reducer,
        settings: BreakSettings(workThreshold: 999, deadTime: 999)
    )
    let event = TimerDiagnosticBuilder.sample(
        sample,
        now: now,
        idleSeconds: 300,
        defaultSettings: BreakSettings(workThreshold: 999, deadTime: 999),
        context: "poll"
    )

    #expect(event.reason == "dead-time")
    #expect(event.threshold == 120)
    #expect(event.deadTime == 300)
    #expect(event.validated == 40)
    #expect(event.provisional == 340)
    #expect(event.overtime == 0)
    #expect(event.recordID == intervalID)
}

@Test func activityAfterDeadTimeDiagnosticDoesNotUseRestartedInterval() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let intervalID = UUID()
    let captured = BreakSettings(workThreshold: 60, deadTime: 300)
    let next = BreakSettings(workThreshold: 999, deadTime: 900)
    let interval = ActiveInterval(
        id: intervalID,
        startedAt: start,
        lastActivityAt: start.addingTimeInterval(20),
        workSegments: [TimeSegment(start: start, end: start.addingTimeInterval(20))],
        settings: captured
    )
    var reducer = TimerReducer(state: TimerState(mode: .active, interval: interval))
    var detector = IdleActivityDetector()
    detector.baseline(at: interval.lastActivityAt)
    let now = start.addingTimeInterval(321.5)

    let sample = PermissionlessHIDPolicy.processSample(
        now: now,
        idleSeconds: 0.4,
        detector: &detector,
        reducer: &reducer,
        settings: next
    )
    let event = TimerDiagnosticBuilder.sample(
        sample,
        now: now,
        idleSeconds: 0.4,
        defaultSettings: next,
        context: "poll"
    )

    #expect(event.reason == "activity-after-dead-time")
    #expect(event.threshold == captured.workThreshold)
    #expect(event.deadTime == captured.deadTime)
    #expect(event.validated == 20)
    #expect(abs(event.provisional! - 321.1) < 0.001)
    #expect(event.overtime == 0)
    #expect(event.recordID == intervalID)
    #expect(sample.stateAfter.interval?.settings == next)
}

@Test func lifecycleDiagnosticReportsActualSaveOutcome() {
    let skipped = LifecycleDiagnosticBuilder.event(
        "sleep",
        stateBefore: .active,
        stateAfter: .active,
        persistence: .skipped
    )
    let failed = LifecycleDiagnosticBuilder.event(
        "quit",
        stateBefore: .active,
        stateAfter: .idle,
        persistence: .failed(type: "DiskFull", message: "not logged")
    )

    #expect(skipped.outcome == "skipped")
    #expect(skipped.reason == nil)
    #expect(failed.outcome == "failed")
    #expect(failed.reason == nil)
    #expect(failed.failureType == "DiskFull")
    #expect(failed.message.contains("DiskFull"))
    #expect(!failed.message.contains("not logged"))
}

@Test func pauseLifecycleDiagnosticIncludesClosureEffect() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var reducer = TimerReducer()
    reducer.activity(at: start, settings: BreakSettings())
    let effects = reducer.pause(at: start.addingTimeInterval(10))
    let record = try #require(effects.compactMap { effect -> HistoryRecord? in
        if case let .log(record) = effect { return record }
        return nil
    }.first)

    let event = LifecycleDiagnosticBuilder.event(
        "pause",
        stateBefore: .active,
        stateAfter: .paused,
        effects: effects,
        persistence: .persisted
    )

    #expect(event.effectKinds == ["history"])
    #expect(event.recordID == record.id)
}

@Test func diagnosticLevelsKeepTransitionsAndWritesAtInfo() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var detector = IdleActivityDetector()
    var reducer = TimerReducer()
    let settings = BreakSettings()

    let started = PermissionlessHIDPolicy.processSample(
        now: start,
        idleSeconds: 0,
        detector: &detector,
        reducer: &reducer,
        settings: settings
    )
    let unchanged = PermissionlessHIDPolicy.processSample(
        now: start.addingTimeInterval(1),
        idleSeconds: 1,
        detector: &detector,
        reducer: &reducer,
        settings: settings
    )

    #expect(started.effects.isEmpty)
    #expect(DiagnosticLevelClassifier.timer(started) == .info)
    #expect(DiagnosticLevelClassifier.timer(unchanged) == .debug)
    #expect(DiagnosticLevelClassifier.persistence(.persisted) == .info)
    #expect(DiagnosticLevelClassifier.persistence(.skipped) == .debug)
    #expect(DiagnosticLevelClassifier.persistence(.blocked) == .error)
    #expect(DiagnosticLevelClassifier.persistence(
        .failed(type: "DiskFull", message: "not logged")
    ) == .error)
}

@Test func relaunchDiagnosticsDistinguishEveryRestoreCause() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let active = TimerState(
        mode: .active,
        interval: ActiveInterval(
            startedAt: start,
            lastActivityAt: start,
            settings: BreakSettings(deadTime: 300)
        )
    )

    #expect(TimerReducer.relaunchReason(
        state: active,
        savedAt: start.addingTimeInterval(10),
        savedSystemUptime: 1_000,
        now: start.addingTimeInterval(20),
        systemUptime: 1_010
    ) == .preserved)
    #expect(TimerReducer.relaunchReason(
        state: active,
        savedAt: start.addingTimeInterval(299),
        now: start.addingTimeInterval(300),
        systemUptime: nil
    ) == .deadTimeClosure)
    #expect(TimerReducer.relaunchReason(
        state: active,
        savedAt: start.addingTimeInterval(10),
        savedSystemUptime: 1_000,
        now: start.addingTimeInterval(20),
        systemUptime: 1_002
    ) == .sleepClosure)
    #expect(TimerReducer.relaunchReason(
        state: active,
        savedAt: start.addingTimeInterval(10),
        savedSystemUptime: 10_000,
        now: start.addingTimeInterval(20),
        systemUptime: 5
    ) == .rebootClosure)
}

@Test func wakeDiagnosticsOnlyClaimClosureForHistoryEffect() {
    let record = HistoryRecord(
        id: UUID(),
        intervalStart: Date(timeIntervalSince1970: 1_700_000_000),
        intervalEnd: Date(timeIntervalSince1970: 1_700_000_010),
        activeDuration: 10,
        overtimeDuration: 0
    )

    #expect(LifecycleDiagnosticReason.wake(
        stateBefore: .active,
        effects: [.log(record)]
    ) == "wake-closes-active")
    #expect(LifecycleDiagnosticReason.wake(
        stateBefore: .idle,
        effects: []
    ) == "wake-no-op")
    #expect(LifecycleDiagnosticReason.wake(
        stateBefore: .paused,
        effects: []
    ) == "wake-preserves-paused")
}

@Test func loginItemDiagnosticsNameNonThrowingFailures() {
    let approval = LoginItemDiagnosticBuilder.configure(
        enabled: true,
        status: .requiresApproval
    )
    let missing = LoginItemDiagnosticBuilder.configure(
        enabled: true,
        status: .notFound
    )

    #expect(approval.outcome == "requires-user-action")
    #expect(approval.reason == "requiresApproval")
    #expect(approval.failureType == "requiresApproval")
    #expect(missing.outcome == "failure")
    #expect(missing.reason == "notFound")
    #expect(missing.failureType == "notFound")
}

@Test func lifecycleFailureDoesNotReplaceRelaunchCause() {
    let event = LifecycleDiagnosticBuilder.event(
        "relaunch",
        reason: RelaunchReason.rebootClosure.rawValue,
        stateBefore: .active,
        stateAfter: .idle,
        persistence: .failed(type: "DiskFull", message: "not logged")
    )

    #expect(event.reason == "reboot-closure")
    #expect(event.failureType == "DiskFull")
}
