import Foundation
import Testing
@testable import ActiveBreakCore

@Test func repairRemovesRepeatedZeroWorkClosuresAndPreservesUniqueRecords() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let duplicateA = zeroWorkRecord(id: UUID(), start: start, breakEnd: start.addingTimeInterval(300))
    let duplicateB = zeroWorkRecord(id: UUID(), start: start, breakEnd: start.addingTimeInterval(301))
    let uniqueZero = zeroWorkRecord(
        id: UUID(),
        start: start.addingTimeInterval(1),
        breakEnd: start.addingTimeInterval(302)
    )
    let valid = HistoryRecord(
        id: UUID(),
        intervalStart: start.addingTimeInterval(10),
        intervalEnd: start.addingTimeInterval(70),
        activeDuration: 60,
        overtimeDuration: 5,
        workSegments: [
            TimeSegment(start: start.addingTimeInterval(10), end: start.addingTimeInterval(70)),
        ]
    )

    let result = HistoryRepair.preview(PersistedData(
        history: [duplicateA, valid, duplicateB, uniqueZero]
    ))

    #expect(result.report.beforeCount == 4)
    #expect(result.report.afterCount == 2)
    #expect(Set(result.report.removedIDs) == [duplicateA.id, duplicateB.id])
    #expect(result.report.retainedIDs == [valid.id, uniqueZero.id])
    #expect(result.report.activeDurationDelta == 0)
    #expect(result.report.overtimeDurationDelta == 0)
    #expect(result.data.history == [valid, uniqueZero])
    #expect(!HistoryRepair.preview(result.data).report.changed)
}

@Test func repairTreatsNearDuplicatesAsDistinct() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let first = zeroWorkRecord(id: UUID(), start: start, breakEnd: start.addingTimeInterval(300))
    let second = zeroWorkRecord(
        id: UUID(),
        start: start.addingTimeInterval(0.001),
        breakEnd: start.addingTimeInterval(300)
    )

    let result = HistoryRepair.preview(PersistedData(history: [first, second]))
    #expect(!result.report.changed)
    #expect(result.data.history == [first, second])
}

@Test func repairApplyCreatesBackupWritesAtomicallyAndIsIdempotent() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let stateURL = directory.appendingPathComponent("state.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let records = [
        zeroWorkRecord(id: UUID(), start: start, breakEnd: start.addingTimeInterval(300)),
        zeroWorkRecord(id: UUID(), start: start, breakEnd: start.addingTimeInterval(301)),
    ]
    try HistoryStore(url: stateURL).save(PersistedData(history: records))
    let original = try Data(contentsOf: stateURL)

    let applied = try HistoryRepair.apply(
        to: stateURL,
        backupDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let backupURL = try #require(applied.backupURL)
    #expect(try Data(contentsOf: backupURL) == original)
    #expect(try HistoryStore(url: stateURL).load().history.isEmpty)
    #expect(try JSONDecoder.activeBreak.decode(
        PersistedData.self,
        from: Data(contentsOf: stateURL)
    ).history.isEmpty)

    let second = try HistoryRepair.apply(
        to: stateURL,
        backupDate: Date(timeIntervalSince1970: 1_700_000_001)
    )
    #expect(!second.report.changed)
    #expect(second.backupURL == nil)
}

@Test func repairRejectsMalformedState() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let stateURL = directory.appendingPathComponent("state.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: stateURL)

    #expect(throws: (any Error).self) {
        try HistoryRepair.apply(to: stateURL)
    }
}

private func zeroWorkRecord(id: UUID, start: Date, breakEnd: Date) -> HistoryRecord {
    HistoryRecord(
        id: id,
        intervalStart: start,
        intervalEnd: start,
        activeDuration: 0,
        overtimeDuration: 0,
        breakStart: start,
        breakEnd: breakEnd,
        workSegments: []
    )
}
