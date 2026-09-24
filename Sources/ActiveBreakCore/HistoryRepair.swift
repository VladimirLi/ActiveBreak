import Foundation

public struct HistoryRepairReport: Codable, Equatable, Sendable {
    public var beforeCount: Int
    public var afterCount: Int
    public var removedIDs: [UUID]
    public var retainedIDs: [UUID]
    public var activeDurationBefore: TimeInterval
    public var activeDurationAfter: TimeInterval
    public var overtimeDurationBefore: TimeInterval
    public var overtimeDurationAfter: TimeInterval

    public var changed: Bool { !removedIDs.isEmpty }
    public var activeDurationDelta: TimeInterval {
        activeDurationAfter - activeDurationBefore
    }
    public var overtimeDurationDelta: TimeInterval {
        overtimeDurationAfter - overtimeDurationBefore
    }
}

public struct HistoryRepairResult: Sendable {
    public var data: PersistedData
    public var report: HistoryRepairReport
}

public struct HistoryRepairApplyResult: Sendable {
    public var report: HistoryRepairReport
    public var backupURL: URL?
}

public enum HistoryRepair {
    public static func preview(_ data: PersistedData) -> HistoryRepairResult {
        let grouped = Dictionary(grouping: data.history.filter(isClosureArtifactCandidate)) {
            ClosureIdentity(record: $0)
        }
        let duplicateIDs = Set(
            grouped.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) }
        )
        var repaired = data
        repaired.history.removeAll { duplicateIDs.contains($0.id) }
        let beforeActive = totalActive(data.history)
        let afterActive = totalActive(repaired.history)
        let beforeOvertime = totalOvertime(data.history)
        let afterOvertime = totalOvertime(repaired.history)
        return HistoryRepairResult(
            data: repaired,
            report: HistoryRepairReport(
                beforeCount: data.history.count,
                afterCount: repaired.history.count,
                removedIDs: data.history.filter { duplicateIDs.contains($0.id) }.map(\.id),
                retainedIDs: repaired.history.map(\.id),
                activeDurationBefore: beforeActive,
                activeDurationAfter: afterActive,
                overtimeDurationBefore: beforeOvertime,
                overtimeDurationAfter: afterOvertime
            )
        )
    }

    public static func apply(
        to stateURL: URL,
        backupDate: Date = .now
    ) throws -> HistoryRepairApplyResult {
        let store = HistoryStore(url: stateURL)
        let current = try store.load()
        let result = preview(current)
        guard result.report.changed else {
            return HistoryRepairApplyResult(report: result.report, backupURL: nil)
        }

        let backupURL = stateURL.deletingLastPathComponent().appendingPathComponent(
            "\(stateURL.lastPathComponent).backup-\(backupName(backupDate))"
        )
        let original = try Data(contentsOf: stateURL)
        guard !FileManager.default.fileExists(atPath: backupURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.copyItem(at: stateURL, to: backupURL)
        do {
            try store.save(result.data)
            let validated = try store.load()
            guard validated == result.data,
                  preview(validated).report.changed == false,
                  totalActive(validated.history) == result.report.activeDurationAfter,
                  totalOvertime(validated.history) == result.report.overtimeDurationAfter
            else {
                throw RepairError.validationFailed
            }
        } catch {
            try? original.write(to: stateURL, options: .atomic)
            throw error
        }
        return HistoryRepairApplyResult(report: result.report, backupURL: backupURL)
    }

    private static func isClosureArtifactCandidate(_ record: HistoryRecord) -> Bool {
        record.activeDuration == 0
            && record.overtimeDuration == 0
            && record.workSegments.isEmpty
            && record.intervalStart == record.intervalEnd
            && record.breakStart == record.intervalEnd
            && record.breakEnd != nil
    }

    private static func totalActive(_ records: [HistoryRecord]) -> TimeInterval {
        records.reduce(0) { $0 + $1.activeDuration }
    }

    private static func totalOvertime(_ records: [HistoryRecord]) -> TimeInterval {
        records.reduce(0) { $0 + $1.overtimeDuration }
    }

    private static func backupName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private struct ClosureIdentity: Hashable {
        let intervalStart: Date
        let intervalEnd: Date
        let activeDuration: TimeInterval
        let overtimeDuration: TimeInterval

        init(record: HistoryRecord) {
            intervalStart = record.intervalStart
            intervalEnd = record.intervalEnd
            activeDuration = record.activeDuration
            overtimeDuration = record.overtimeDuration
        }
    }

    private enum RepairError: Error {
        case validationFailed
    }
}
