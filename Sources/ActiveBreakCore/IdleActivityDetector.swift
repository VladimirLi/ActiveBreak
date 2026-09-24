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
