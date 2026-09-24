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

public struct ActiveInterval: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var lastActivityAt: Date
    public var validatedActive: TimeInterval
    public var settings: BreakSettings
    public var notificationSent: Bool

    public init(
        startedAt: Date,
        lastActivityAt: Date,
        validatedActive: TimeInterval = 0,
        settings: BreakSettings,
        notificationSent: Bool = false
    ) {
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.validatedActive = validatedActive
        self.settings = settings
        self.notificationSent = notificationSent
    }

    public func provisionalActive(at date: Date) -> TimeInterval {
        validatedActive + max(0, date.timeIntervalSince(lastActivityAt))
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

    public init(
        id: UUID = UUID(),
        intervalStart: Date,
        intervalEnd: Date,
        activeDuration: TimeInterval,
        overtimeDuration: TimeInterval,
        breakStart: Date? = nil,
        breakEnd: Date? = nil
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
    }
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
