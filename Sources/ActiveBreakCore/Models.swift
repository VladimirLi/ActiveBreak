import Foundation

public struct BreakSettings: Codable, Equatable, Sendable {
    public var workThreshold: TimeInterval
    public var deadTime: TimeInterval
    public var notificationsEnabled: Bool
    public var soundEnabled: Bool
    public var launchAtLogin: Bool

    public init(
        workThreshold: TimeInterval = 25 * 60,
        deadTime: TimeInterval = 5 * 60,
        notificationsEnabled: Bool = true,
        soundEnabled: Bool = true,
        launchAtLogin: Bool = true
    ) {
        self.workThreshold = workThreshold
        self.deadTime = deadTime
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.launchAtLogin = launchAtLogin
    }
}

public struct TimeSegment: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var isOvertime: Bool

    public init(start: Date, end: Date, isOvertime: Bool = false) {
        self.start = start
        self.end = end
        self.isOvertime = isOvertime
    }

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

public struct ActiveInterval: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var lastActivityAt: Date
    public var workSegments: [TimeSegment]
    public var excludedGaps: [TimeSegment]
    public var settings: BreakSettings
    public var notificationSent: Bool

    public init(
        startedAt: Date,
        lastActivityAt: Date,
        validatedActive: TimeInterval = 0,
        workSegments: [TimeSegment]? = nil,
        excludedGaps: [TimeSegment] = [],
        settings: BreakSettings,
        notificationSent: Bool = false
    ) {
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.workSegments = workSegments ?? Self.legacySegments(
            start: startedAt,
            duration: validatedActive,
            threshold: settings.workThreshold
        )
        self.excludedGaps = excludedGaps
        self.settings = settings
        self.notificationSent = notificationSent
    }

    public var validatedActive: TimeInterval {
        workSegments.reduce(0) { $0 + $1.duration }
    }

    public var overtime: TimeInterval {
        workSegments.filter(\.isOvertime).reduce(0) { $0 + $1.duration }
    }

    public func provisionalActive(at date: Date) -> TimeInterval {
        validatedActive + unresolvedWork(through: date).reduce(0) { $0 + $1.duration }
    }

    public func unresolvedWork(through date: Date) -> [TimeSegment] {
        subtract(excludedGaps, from: TimeSegment(start: lastActivityAt, end: date))
    }

    private enum CodingKeys: String, CodingKey {
        case startedAt
        case lastActivityAt
        case validatedActive
        case workSegments
        case excludedGaps
        case settings
        case notificationSent
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(lastActivityAt, forKey: .lastActivityAt)
        try container.encode(validatedActive, forKey: .validatedActive)
        try container.encode(workSegments, forKey: .workSegments)
        try container.encode(excludedGaps, forKey: .excludedGaps)
        try container.encode(settings, forKey: .settings)
        try container.encode(notificationSent, forKey: .notificationSent)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        lastActivityAt = try container.decode(Date.self, forKey: .lastActivityAt)
        settings = try container.decode(BreakSettings.self, forKey: .settings)
        notificationSent = try container.decode(Bool.self, forKey: .notificationSent)
        excludedGaps = try container.decodeIfPresent([TimeSegment].self, forKey: .excludedGaps) ?? []
        if let segments = try container.decodeIfPresent([TimeSegment].self, forKey: .workSegments) {
            workSegments = segments
        } else {
            let duration = try container.decodeIfPresent(TimeInterval.self, forKey: .validatedActive) ?? 0
            workSegments = Self.legacySegments(
                start: startedAt,
                duration: duration,
                threshold: settings.workThreshold
            )
        }
    }

    private static func legacySegments(
        start: Date,
        duration: TimeInterval,
        threshold: TimeInterval
    ) -> [TimeSegment] {
        guard duration > 0 else { return [] }
        let regular = min(duration, threshold)
        var segments = [TimeSegment(start: start, end: start.addingTimeInterval(regular))]
        if duration > threshold {
            segments.append(TimeSegment(
                start: start.addingTimeInterval(threshold),
                end: start.addingTimeInterval(duration),
                isOvertime: true
            ))
        }
        return segments
    }
}

public struct HistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var intervalStart: Date
    public var intervalEnd: Date
    public var activeDuration: TimeInterval
    public var overtimeDuration: TimeInterval
    public var breakStart: Date?
    public var breakEnd: Date?
    public var breakDuration: TimeInterval
    public var workSegments: [TimeSegment]

    public init(
        id: UUID = UUID(),
        intervalStart: Date,
        intervalEnd: Date,
        activeDuration: TimeInterval,
        overtimeDuration: TimeInterval,
        breakStart: Date? = nil,
        breakEnd: Date? = nil,
        workSegments: [TimeSegment]? = nil
    ) {
        self.id = id
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.activeDuration = max(0, activeDuration)
        self.overtimeDuration = max(0, overtimeDuration)
        self.breakStart = breakStart
        self.breakEnd = breakEnd
        if let breakStart, let breakEnd {
            self.breakDuration = max(0, breakEnd.timeIntervalSince(breakStart))
        } else {
            self.breakDuration = 0
        }
        self.workSegments = workSegments ?? Self.legacySegments(
            start: intervalStart,
            activeDuration: activeDuration,
            overtimeDuration: overtimeDuration
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case intervalStart
        case intervalEnd
        case activeDuration
        case overtimeDuration
        case breakStart
        case breakEnd
        case breakDuration
        case workSegments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(intervalStart, forKey: .intervalStart)
        try container.encode(intervalEnd, forKey: .intervalEnd)
        try container.encode(activeDuration, forKey: .activeDuration)
        try container.encode(overtimeDuration, forKey: .overtimeDuration)
        try container.encode(breakStart, forKey: .breakStart)
        try container.encode(breakEnd, forKey: .breakEnd)
        try container.encode(breakDuration, forKey: .breakDuration)
        try container.encode(workSegments, forKey: .workSegments)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        intervalStart = try container.decode(Date.self, forKey: .intervalStart)
        intervalEnd = try container.decode(Date.self, forKey: .intervalEnd)
        activeDuration = try container.decode(TimeInterval.self, forKey: .activeDuration)
        overtimeDuration = try container.decode(TimeInterval.self, forKey: .overtimeDuration)
        breakStart = try container.decodeIfPresent(Date.self, forKey: .breakStart)
        breakEnd = try container.decodeIfPresent(Date.self, forKey: .breakEnd)
        if let storedDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .breakDuration) {
            breakDuration = storedDuration
        } else if let breakStart, let breakEnd {
            breakDuration = max(0, breakEnd.timeIntervalSince(breakStart))
        } else {
            breakDuration = 0
        }
        workSegments = try container.decodeIfPresent([TimeSegment].self, forKey: .workSegments)
            ?? Self.legacySegments(
                start: intervalStart,
                activeDuration: activeDuration,
                overtimeDuration: overtimeDuration
            )
    }

    private static func legacySegments(
        start: Date,
        activeDuration: TimeInterval,
        overtimeDuration: TimeInterval
    ) -> [TimeSegment] {
        guard activeDuration > 0 else { return [] }
        let regularDuration = max(0, activeDuration - overtimeDuration)
        var segments: [TimeSegment] = []
        if regularDuration > 0 {
            segments.append(TimeSegment(
                start: start,
                end: start.addingTimeInterval(regularDuration)
            ))
        }
        if overtimeDuration > 0 {
            segments.append(TimeSegment(
                start: start.addingTimeInterval(regularDuration),
                end: start.addingTimeInterval(activeDuration),
                isOvertime: true
            ))
        }
        return segments
    }
}

public func subtract(_ exclusions: [TimeSegment], from segment: TimeSegment) -> [TimeSegment] {
    guard segment.end > segment.start else { return [] }
    var result = [segment]
    for exclusion in exclusions {
        result = result.flatMap { candidate in
            guard exclusion.end > candidate.start, exclusion.start < candidate.end else {
                return [candidate]
            }
            var pieces: [TimeSegment] = []
            if exclusion.start > candidate.start {
                pieces.append(TimeSegment(start: candidate.start, end: min(exclusion.start, candidate.end)))
            }
            if exclusion.end < candidate.end {
                pieces.append(TimeSegment(start: max(exclusion.end, candidate.start), end: candidate.end))
            }
            return pieces
        }
    }
    return result
}

public enum TimerMode: String, Codable, Equatable, Sendable {
    case idle
    case active
    case paused
}

public struct TimerState: Codable, Equatable, Sendable {
    public var mode: TimerMode
    public var interval: ActiveInterval?

    public init(mode: TimerMode = .idle, interval: ActiveInterval? = nil) {
        self.mode = mode
        self.interval = interval
    }
}

public struct PersistedData: Codable, Equatable, Sendable {
    public var settings: BreakSettings
    public var timer: TimerState
    public var history: [HistoryRecord]
    public var savedAt: Date

    public init(
        settings: BreakSettings = BreakSettings(),
        timer: TimerState = TimerState(),
        history: [HistoryRecord] = [],
        savedAt: Date = .now
    ) {
        self.settings = settings
        self.timer = timer
        self.history = history
        self.savedAt = savedAt
    }
}
