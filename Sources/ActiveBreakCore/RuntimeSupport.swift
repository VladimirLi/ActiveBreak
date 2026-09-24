import Foundation

public struct TimerEffectApplicationResult: Sendable {
    public var data: PersistedData
    public var forwardedEffects: [TimerEffect]
    public var historyChanged: Bool
    public var stateChanged: Bool
}

public enum TimerEffectProcessor {
    public static func apply(
        _ effects: [TimerEffect],
        state: TimerState,
        to data: PersistedData
    ) -> TimerEffectApplicationResult {
        var updated = data
        var forwarded: [TimerEffect] = []
        var historyChanged = false
        for effect in effects {
            if case let .log(record) = effect {
                guard !updated.history.contains(where: { $0.id == record.id }) else { continue }
                updated.history.append(record)
                historyChanged = true
            } else {
                forwarded.append(effect)
            }
        }
        let stateChanged = updated.timer != state
        updated.timer = state
        return TimerEffectApplicationResult(
            data: updated,
            forwardedEffects: forwarded,
            historyChanged: historyChanged,
            stateChanged: stateChanged
        )
    }
}

public struct PersistenceCadence: Sendable {
    public let checkpointInterval: TimeInterval
    private var lastSavedAt: Date?

    public init(checkpointInterval: TimeInterval = 60, lastSavedAt: Date? = nil) {
        self.checkpointInterval = checkpointInterval
        self.lastSavedAt = lastSavedAt
    }

    public mutating func shouldSave(
        at date: Date,
        changed: Bool,
        force: Bool = false
    ) -> Bool {
        let checkpointDue = lastSavedAt.map {
            date.timeIntervalSince($0) >= checkpointInterval
        } ?? true
        guard force || changed || checkpointDue else { return false }
        lastSavedAt = date
        return true
    }

    public mutating func markSaveFailed() {
        lastSavedAt = nil
    }
}
