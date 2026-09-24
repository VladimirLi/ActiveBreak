import ActiveBreakCore
import Foundation

let environment = ProcessInfo.processInfo.environment
guard let statePath = environment["ACTIVEBREAK_STATE_FILE"] else {
    FileHandle.standardError.write(Data("ACTIVEBREAK_STATE_FILE is required\n".utf8))
    exit(64)
}

let arguments = Array(CommandLine.arguments.dropFirst())
func value(after option: String) -> String? {
    guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

let store = HistoryStore(url: URL(fileURLWithPath: statePath))
let iterations = Int(value(after: "--iterations") ?? "600") ?? 600
let benchmark = value(after: "--benchmark")
let started = Date()
var writes = 0

func verifyRepeatedClosureProtection(settings: BreakSettings) throws {
    struct RepeatedClosure: Error {}

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var detector = IdleActivityDetector()
    var reducer = TimerReducer()
    var history: [HistoryRecord] = []

    func process(now: Date, idleSeconds: TimeInterval) {
        let sample = PermissionlessHIDPolicy.processSample(
            now: now,
            idleSeconds: idleSeconds,
            detector: &detector,
            reducer: &reducer,
            settings: settings
        )
        history = TimerEffectProcessor.apply(
            sample.effects,
            state: reducer.state,
            to: PersistedData(settings: settings, history: history)
        ).data.history
    }

    process(now: start, idleSeconds: 0)
    process(now: start.addingTimeInterval(10), idleSeconds: 0)
    process(now: start.addingTimeInterval(130), idleSeconds: 120)
    for sample in 1...20 {
        let now = start.addingTimeInterval(130 + Double(sample))
        let staleEvent = start.addingTimeInterval(10 + Double(sample) * 0.005)
        process(now: now, idleSeconds: now.timeIntervalSince(staleEvent))
    }
    guard history.count == 1, reducer.state.mode == .idle else {
        throw RepeatedClosure()
    }
}

do {
    var data = try store.load()
    try verifyRepeatedClosureProtection(
        settings: BreakSettings(workThreshold: 600, deadTime: 120)
    )
    var reducer = TimerReducer(state: data.timer)
    let first = Date()
    _ = reducer.activity(at: first, settings: data.settings)
    data.timer = reducer.state
    var cadence = PersistenceCadence(checkpointInterval: 60)

    for tick in 0..<iterations {
        let now = first.addingTimeInterval(Double(tick) / 100)
        let shouldWrite: Bool
        if benchmark == "legacy" {
            shouldWrite = true
        } else {
            shouldWrite = cadence.shouldSave(at: now, changed: tick == 0)
        }
        if shouldWrite {
            var snapshot = data
            snapshot.savedAt = now
            snapshot.savedSystemUptime = ProcessInfo.processInfo.systemUptime
            try store.save(snapshot)
            writes += 1
        }
    }

    let finalEffects = reducer.pause(at: first.addingTimeInterval(Double(iterations) / 100))
    data = TimerEffectProcessor.apply(finalEffects, state: reducer.state, to: data).data
    data.savedAt = Date()
    data.savedSystemUptime = ProcessInfo.processInfo.systemUptime
    try store.save(data)
    writes += 1

    let elapsed = Date().timeIntervalSince(started)
    print("mode=\(benchmark ?? "smoke") iterations=\(iterations) writes=\(writes) elapsed=\(elapsed)")
} catch {
    FileHandle.standardError.write(Data("ActiveBreakSmoke failed: \(error)\n".utf8))
    exit(1)
}
