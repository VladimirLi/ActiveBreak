import Foundation
import Testing

@Test func pollingDoesNotPublishClockOrPersistEverySecond() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let appModel = try String(
        contentsOf: repository.appendingPathComponent("Sources/ActiveBreak/AppModel.swift"),
        encoding: .utf8
    )

    #expect(!appModel.contains("@Published private(set) var now"))
    #expect(appModel.contains("PersistenceCadence"))
    #expect(appModel.contains("status.update"))
}
