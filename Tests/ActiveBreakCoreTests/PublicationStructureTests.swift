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
    #expect(appModel.contains("PersistenceController"))
    #expect(appModel.contains("status.update"))

    let pauseStart = try #require(appModel.range(of: "func togglePause()"))
    let pauseEnd = try #require(appModel.range(
        of: "func updateSettings",
        range: pauseStart.upperBound..<appModel.endIndex
    ))
    let pauseBody = appModel[pauseStart.lowerBound..<pauseEnd.lowerBound]
    #expect(pauseBody.contains("let effects: [TimerEffect]"))
    #expect(pauseBody.contains("effects: effects"))
    #expect(appModel.contains("DiagnosticLevelClassifier.timer(sample)"))
    #expect(appModel.contains("DiagnosticLevelClassifier.persistence(result)"))
}
