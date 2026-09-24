import Foundation

public enum TimerEffect: Equatable, Sendable {
    case notify(sound: Bool)
    case playSound
    case log(HistoryRecord)
}

public struct TimerReducer: Sendable {
    public private(set) var state: TimerState

    public init(state: TimerState = TimerState()) {
        self.state = state
    }

    @discardableResult
    public mutating func activity(at date: Date, settings: BreakSettings) -> [TimerEffect] {
        guard state.mode != .paused else { return [] }
        guard var interval = state.interval else {
            state = TimerState(
                mode: .active,
                interval: ActiveInterval(startedAt: date, lastActivityAt: date, settings: settings)
            )
            return []
        }

        let gap = max(0, date.timeIntervalSince(interval.lastActivityAt))
        guard gap < interval.settings.deadTime else {
            let effects = close(interval: interval, breakEnd: date)
            state = TimerState(
                mode: .active,
                interval: ActiveInterval(startedAt: date, lastActivityAt: date, settings: settings)
            )
            return effects
        }

        interval.validatedActive += gap
        interval.lastActivityAt = date
        state.interval = interval
        return thresholdEffects(at: date)
    }

    @discardableResult
    public mutating func sample(at date: Date) -> [TimerEffect] {
        guard state.mode == .active, let interval = state.interval else { return [] }
        let gap = max(0, date.timeIntervalSince(interval.lastActivityAt))
        if gap >= interval.settings.deadTime {
            state = TimerState()
            return close(interval: interval, breakEnd: date)
        }
        return thresholdEffects(at: date)
    }

    @discardableResult
    public mutating func pause(at date: Date) -> [TimerEffect] {
        guard state.mode != .paused else { return [] }
        defer { state = TimerState(mode: .paused) }
        guard let interval = state.interval else { return [] }
        return [.log(record(for: interval, breakEnd: nil))]
    }

    public mutating func resume() {
        state = TimerState()
    }

    @discardableResult
    public mutating func restore(savedAt: Date, now: Date) -> [TimerEffect] {
        guard state.mode == .active, var interval = state.interval else { return [] }
        let downtime = max(0, now.timeIntervalSince(savedAt))
        if downtime >= interval.settings.deadTime {
            state = TimerState()
            return close(interval: interval, breakEnd: now)
        }
        interval.lastActivityAt = interval.lastActivityAt.addingTimeInterval(downtime)
        state.interval = interval
        return []
    }

    @discardableResult
    public mutating func wake(at date: Date) -> [TimerEffect] {
        guard state.mode == .active, let interval = state.interval else {
            state = state.mode == .paused ? TimerState(mode: .paused) : TimerState()
            return []
        }
        state = TimerState()
        return close(interval: interval, breakEnd: date)
    }

    public func remaining(at date: Date, defaultSettings: BreakSettings) -> TimeInterval {
        guard state.mode == .active, let interval = state.interval else {
            return defaultSettings.workThreshold
        }
        return interval.settings.workThreshold - interval.provisionalActive(at: date)
    }

    private mutating func thresholdEffects(at date: Date) -> [TimerEffect] {
        guard var interval = state.interval,
              !interval.notificationSent,
              interval.provisionalActive(at: date) >= interval.settings.workThreshold
        else { return [] }

        interval.notificationSent = true
        state.interval = interval
        if interval.settings.notificationsEnabled {
            return [.notify(sound: interval.settings.soundEnabled)]
        }
        return interval.settings.soundEnabled ? [.playSound] : []
    }

    private func close(interval: ActiveInterval, breakEnd: Date?) -> [TimerEffect] {
        [.log(record(for: interval, breakEnd: breakEnd))]
    }

    private func record(for interval: ActiveInterval, breakEnd: Date?) -> HistoryRecord {
        HistoryRecord(
            intervalStart: interval.startedAt,
            intervalEnd: interval.lastActivityAt,
            activeDuration: interval.validatedActive,
            overtimeDuration: max(0, interval.validatedActive - interval.settings.workThreshold),
            breakStart: breakEnd == nil ? nil : interval.lastActivityAt,
            breakEnd: breakEnd
        )
    }
}

public enum CountdownFormatter {
    public static func string(seconds: TimeInterval) -> String {
        let overdue = seconds < 0
        let value = Int(abs(seconds).rounded(.down))
        let text: String
        if value >= 3600 {
            text = "\(value / 3600)h \((value % 3600) / 60)m"
        } else {
            text = String(format: "%02d:%02d", value / 60, value % 60)
        }
        return overdue ? "-\(text)" : text
    }
}
