import Foundation

public enum DiagnosticCategory: String, Codable, Sendable {
    case timer
    case lifecycle
    case persistence
    case loginItem
}

public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public var category: DiagnosticCategory
    public var event: String
    public var reason: String?
    public var stateBefore: TimerMode?
    public var stateAfter: TimerMode?
    public var idleSeconds: TimeInterval?
    public var inferredEventAt: Date?
    public var threshold: TimeInterval?
    public var deadTime: TimeInterval?
    public var validated: TimeInterval?
    public var provisional: TimeInterval?
    public var overtime: TimeInterval?
    public var effectKinds: [String]?
    public var recordID: UUID?
    public var outcome: String?

    public init(
        category: DiagnosticCategory,
        event: String,
        reason: String? = nil,
        stateBefore: TimerMode? = nil,
        stateAfter: TimerMode? = nil,
        idleSeconds: TimeInterval? = nil,
        inferredEventAt: Date? = nil,
        threshold: TimeInterval? = nil,
        deadTime: TimeInterval? = nil,
        validated: TimeInterval? = nil,
        provisional: TimeInterval? = nil,
        overtime: TimeInterval? = nil,
        effectKinds: [String]? = nil,
        recordID: UUID? = nil,
        outcome: String? = nil
    ) {
        self.category = category
        self.event = event
        self.reason = reason
        self.stateBefore = stateBefore
        self.stateAfter = stateAfter
        self.idleSeconds = idleSeconds
        self.inferredEventAt = inferredEventAt
        self.threshold = threshold
        self.deadTime = deadTime
        self.validated = validated
        self.provisional = provisional
        self.overtime = overtime
        self.effectKinds = effectKinds
        self.recordID = recordID
        self.outcome = outcome
    }

    public var message: String {
        (try? String(data: JSONEncoder.activeBreak.encode(self), encoding: .utf8)) ?? "{}"
    }
}

public extension TimerEffect {
    var diagnosticKind: String {
        switch self {
        case .notify:
            return "notification"
        case .playSound:
            return "sound"
        case .log:
            return "history"
        }
    }
}
