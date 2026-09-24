import Foundation

public struct IdleActivityDetector: Sendable {
    public let timestampTolerance: TimeInterval
    public let initialActivityWindow: TimeInterval
    public private(set) var lastEventAt: Date?

    public init(
        timestampTolerance: TimeInterval = 0.1,
        initialActivityWindow: TimeInterval = 1.5
    ) {
        self.timestampTolerance = timestampTolerance
        self.initialActivityWindow = initialActivityWindow
    }

    public mutating func baseline(at date: Date) {
        lastEventAt = date
    }

    public mutating func activityDate(now: Date, idleSeconds: TimeInterval) -> Date? {
        let idle = max(0, idleSeconds)
        let eventAt = now.addingTimeInterval(-idle)
        guard let previous = lastEventAt else {
            lastEventAt = eventAt
            return idle <= initialActivityWindow ? eventAt : nil
        }
        guard eventAt.timeIntervalSince(previous) > timestampTolerance else { return nil }
        lastEventAt = eventAt
        return eventAt
    }
}

public enum LaunchAtLoginStatus: Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public enum LaunchAtLoginAction: Equatable, Sendable {
    case none
    case register
    case unregister
}

public enum LaunchAtLoginPolicy {
    public static func action(
        enabled: Bool,
        status: LaunchAtLoginStatus
    ) -> LaunchAtLoginAction {
        switch (enabled, status) {
        case (true, .notRegistered):
            return .register
        case (false, .enabled), (false, .requiresApproval):
            return .unregister
        default:
            return .none
        }
    }

    public static func errorMessage(
        enabled: Bool,
        status: LaunchAtLoginStatus
    ) -> String? {
        switch status {
        case .notFound:
            return "ActiveBreak could not be found by macOS Login Items."
        case .requiresApproval where enabled:
            return "Open System Settings to approve ActiveBreak as a login item."
        default:
            return nil
        }
    }
}

public enum StateFileLocator {
    public static func url(
        environment: [String: String],
        applicationSupport: URL
    ) -> URL {
        environment["ACTIVEBREAK_STATE_FILE"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        } ?? applicationSupport
            .appendingPathComponent("ActiveBreak", isDirectory: true)
            .appendingPathComponent("state.json")
    }
}
