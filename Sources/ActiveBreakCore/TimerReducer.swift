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

        let activityBoundary = interval.excludedGaps.reduce(interval.lastActivityAt) {
            max($0, $1.end)
        }
        guard date > activityBoundary else { return [] }

        let gap = max(0, date.timeIntervalSince(interval.lastActivityAt))
        guard gap < interval.settings.deadTime else {
            let effects = close(interval: interval, breakEnd: date)
            state = TimerState(
                mode: .active,
                interval: ActiveInterval(startedAt: date, lastActivityAt: date, settings: settings)
            )
            return effects
        }

        appendValidated(interval.unresolvedWork(through: date), to: &interval)
        interval.excludedGaps.removeAll()
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
        let totalGap = max(0, now.timeIntervalSince(interval.lastActivityAt))
        if totalGap >= interval.settings.deadTime {
            state = TimerState()
            return close(interval: interval, breakEnd: now)
        }
        if downtime > 0 {
            interval.excludedGaps.append(TimeSegment(start: savedAt, end: now))
        }
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
            overtimeDuration: interval.overtime,
            breakStart: breakEnd == nil ? nil : interval.lastActivityAt,
            breakEnd: breakEnd,
            workSegments: interval.workSegments
        )
    }

    private func appendValidated(_ segments: [TimeSegment], to interval: inout ActiveInterval) {
        var validated = interval.validatedActive
        for segment in segments where segment.duration > 0 {
            let regularRemaining = max(0, interval.settings.workThreshold - validated)
            if regularRemaining > 0 {
                let regularEnd = min(segment.end, segment.start.addingTimeInterval(regularRemaining))
                append(TimeSegment(start: segment.start, end: regularEnd), to: &interval.workSegments)
                validated += regularEnd.timeIntervalSince(segment.start)
                if regularEnd < segment.end {
                    append(TimeSegment(
                        start: regularEnd,
                        end: segment.end,
                        isOvertime: true
                    ), to: &interval.workSegments)
                    validated += segment.end.timeIntervalSince(regularEnd)
                }
            } else {
                append(TimeSegment(
                    start: segment.start,
                    end: segment.end,
                    isOvertime: true
                ), to: &interval.workSegments)
                validated += segment.duration
            }
        }
    }

    private func append(_ segment: TimeSegment, to segments: inout [TimeSegment]) {
        if let last = segments.last,
           last.isOvertime == segment.isOvertime,
           abs(last.end.timeIntervalSince(segment.start)) < 0.001 {
            segments[segments.count - 1].end = segment.end
        } else {
            segments.append(segment)
        }
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
