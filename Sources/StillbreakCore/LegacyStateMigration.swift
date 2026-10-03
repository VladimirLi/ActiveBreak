import CryptoKit
import Foundation

/// Imports history and settings from the pre-rename "ActiveBreak" Application
/// Support folder, and keeps folding in anything ActiveBreak writes afterwards
/// (it can be relaunched by its old login item). The legacy file is never
/// modified or removed. The exact legacy bytes last imported are kept beside
/// the Stillbreak state file as the merge base, so a later launch can tell what
/// ActiveBreak added without resurrecting history Stillbreak has since removed.
public enum LegacyStateMigration {
    public enum Outcome: Equatable, Sendable {
        case notNeeded
        case migrated
        case merged(addedRecords: Int)
    }

    public enum Failure: Error, Equatable, LocalizedError, Sendable {
        case legacyAppRunning

        public var errorDescription: String? {
            "ActiveBreak is still running. Quit it from its menu, then relaunch Stillbreak to import your history."
        }
    }

    public static let legacyFolderName = "ActiveBreak"
    public static let legacyBundleIdentifier = "com.vladimirli.ActiveBreak"
    public static let baseFileName = "legacy-import-base.json"

    public static func legacyURL(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent(legacyFolderName, isDirectory: true)
            .appendingPathComponent("state.json")
    }

    public static func baseURL(current: URL) -> URL {
        current.deletingLastPathComponent().appendingPathComponent(baseFileName)
    }

    /// No Stillbreak state yet: copies `legacy` to `current`, refusing while the
    /// legacy app runs so the first state is not an instantly stale snapshot.
    /// Stillbreak state already exists: when `legacy` differs from the last
    /// import, merges what ActiveBreak added since (a running legacy app is
    /// fine, the next launch folds in whatever it writes later). Throws on any
    /// failure so callers never start from, or save over, state that is missing
    /// legacy data.
    public static func migrateIfNeeded(
        current: URL,
        legacy: URL,
        legacyAppIsRunning: () -> Bool = { false },
        fileManager: FileManager = .default
    ) throws -> Outcome {
        guard fileManager.fileExists(atPath: legacy.path) else { return .notNeeded }
        let legacyBytes = try Data(contentsOf: legacy)
        let base = baseURL(current: current)
        if !fileManager.fileExists(atPath: current.path) {
            guard !legacyAppIsRunning() else { throw Failure.legacyAppRunning }
            try importLegacy(legacyBytes, to: current, base: base, fileManager: fileManager)
            return .migrated
        }
        let baseBytes = try? Data(contentsOf: base)
        if baseBytes == legacyBytes { return .notNeeded }
        return try merge(legacyBytes, baseBytes: baseBytes, current: current, base: base)
    }

    private static func importLegacy(
        _ bytes: Data,
        to current: URL,
        base: URL,
        fileManager: FileManager
    ) throws {
        let directory = current.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".state.json.migrating-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try bytes.write(to: temporary)
        // Base first: a crash before state.json exists just repeats the import.
        try bytes.write(to: base, options: .atomic)
        try fileManager.moveItem(at: temporary, to: current)
    }

    private static func merge(
        _ legacyBytes: Data,
        baseBytes: Data?,
        current: URL,
        base: URL
    ) throws -> Outcome {
        let decoder = JSONDecoder.stillbreak
        let legacyData = try decoder.decode(PersistedData.self, from: legacyBytes)
        // An unreadable base only costs resurrecting records removed from
        // Stillbreak; adding too much is safer than dropping ActiveBreak data.
        let baseHistory = baseBytes.flatMap { try? decoder.decode(PersistedData.self, from: $0) }?.history ?? []
        let baseRecords = Dictionary(baseHistory.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let store = HistoryStore(url: current)
        let original = try store.load()
        var merged = original
        let currentRecords = Dictionary(
            merged.history.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var knownIDs = Set(currentRecords.keys).union(baseRecords.keys)
        var added: [HistoryRecord] = []
        for record in legacyData.history {
            if let existing = currentRecords[record.id] {
                // Both apps closed the same inherited interval with different
                // data. Keep Stillbreak's record and also keep the legacy one
                // under a derived ID, unless ActiveBreak never changed it.
                guard existing != record, baseRecords[record.id] != record else { continue }
                var copy = record
                copy.id = try conflictID(for: record)
                if knownIDs.insert(copy.id).inserted { added.append(copy) }
            } else if knownIDs.insert(record.id).inserted {
                added.append(record)
            }
        }
        added.sort { $0.intervalStart < $1.intervalStart }
        merged.history.append(contentsOf: added)
        if legacyData.savedAt > merged.savedAt {
            merged.settings = legacyData.settings
            merged.timer = legacyData.timer
            merged.savedAt = legacyData.savedAt
            merged.savedSystemUptime = legacyData.savedSystemUptime
        }
        if merged != original { try store.save(merged) }
        // Base last: a crash before this repeats an idempotent merge.
        try legacyBytes.write(to: base, options: .atomic)
        return .merged(addedRecords: added.count)
    }

    /// Stable across retries, so a crash between saving the merge and
    /// recording the base cannot add the same conflicting record twice.
    private static func conflictID(for record: HistoryRecord) throws -> UUID {
        let digest = SHA256.hash(data: try JSONEncoder.stillbreak.encode(record))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
