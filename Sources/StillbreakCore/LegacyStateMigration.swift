import Foundation

/// One-time copy of history and settings from the pre-rename "ActiveBreak"
/// Application Support folder. The legacy file is never modified or removed,
/// so the old app keeps working and the data can be re-migrated if needed.
/// The copy is refused while ActiveBreak is running, because it would keep
/// writing history that a one-time snapshot could not capture.
public enum LegacyStateMigration {
    public enum Outcome: Equatable, Sendable {
        case notNeeded
        case migrated
    }

    public enum Failure: Error, Equatable, LocalizedError, Sendable {
        case legacyAppRunning

        public var errorDescription: String? {
            "ActiveBreak is still running. Quit it from its menu, then relaunch Stillbreak to import your history."
        }
    }

    public static let legacyFolderName = "ActiveBreak"
    public static let legacyBundleIdentifier = "com.vladimirli.ActiveBreak"

    public static func legacyURL(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent(legacyFolderName, isDirectory: true)
            .appendingPathComponent("state.json")
    }

    /// Copies `legacy` to `current` only when `current` does not exist and
    /// `legacy` does. Throws if the copy fails or the legacy app is running so
    /// callers can avoid starting from an empty state that would later shadow
    /// the legacy history.
    public static func migrateIfNeeded(
        current: URL,
        legacy: URL,
        legacyAppIsRunning: () -> Bool = { false },
        fileManager: FileManager = .default
    ) throws -> Outcome {
        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path)
        else {
            return .notNeeded
        }
        guard !legacyAppIsRunning() else { throw Failure.legacyAppRunning }
        let directory = current.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".state.json.migrating-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: legacy, to: temporary)
        try fileManager.moveItem(at: temporary, to: current)
        return .migrated
    }
}
