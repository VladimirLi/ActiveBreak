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

do {
    var data = try store.load()
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
