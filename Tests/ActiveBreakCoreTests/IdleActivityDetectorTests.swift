import Foundation
import Testing
@testable import ActiveBreakCore

@Test func repeatedIdleSamplesFromOneEventEmitActivityOnce() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var detector = IdleActivityDetector()

    #expect(detector.activityDate(now: start, idleSeconds: 0.2) == start.addingTimeInterval(-0.2))
    #expect(detector.activityDate(now: start.addingTimeInterval(1), idleSeconds: 1.2) == nil)
    #expect(detector.activityDate(now: start.addingTimeInterval(2), idleSeconds: 2.2) == nil)
}

@Test func latePollUsesActualEventTimeBeforeDeadTimeBoundary() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var detector = IdleActivityDetector()
    var reducer = TimerReducer()
    let settings = BreakSettings(workThreshold: 600, deadTime: 300)

    let initialEvent = detector.activityDate(now: start, idleSeconds: 0)
    reducer.activity(at: initialEvent!, settings: settings)

    let pollAt = start.addingTimeInterval(300.2)
    let eventAt = detector.activityDate(now: pollAt, idleSeconds: 0.3)
    #expect(abs(eventAt!.timeIntervalSince(start) - 299.9) < 0.001)
    reducer.activity(at: eventAt!, settings: settings)
    reducer.sample(at: pollAt)

    #expect(reducer.state.mode == .active)
    #expect(abs(reducer.state.interval!.validatedActive - 299.9) < 0.001)
}

@Test func stateFileOverrideDoesNotUseApplicationSupport() {
    let support = URL(fileURLWithPath: "/Users/example/Library/Application Support")
    let override = "/tmp/activebreak-test/state.json"
    #expect(StateFileLocator.url(
        environment: ["ACTIVEBREAK_STATE_FILE": override],
        applicationSupport: support
    ).path == override)
    #expect(StateFileLocator.url(
        environment: [:],
        applicationSupport: support
    ).path == "/Users/example/Library/Application Support/ActiveBreak/state.json")
}
