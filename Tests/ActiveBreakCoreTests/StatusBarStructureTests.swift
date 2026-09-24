import Foundation
import Testing

@Test func menuBarLabelIsTextOnlyCountdown() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repository.appendingPathComponent("Sources/ActiveBreak/ActiveBreakApp.swift"),
        encoding: .utf8
    )
    let menuBar = try #require(source.range(of: "MenuBarExtra {"))
    let style = try #require(source.range(
        of: ".menuBarExtraStyle",
        range: menuBar.lowerBound..<source.endIndex
    ))
    let labelBlock = source[menuBar.lowerBound..<style.lowerBound]
    #expect(labelBlock.contains("StatusBarCountdown("))

    let component = try #require(source.range(of: "private struct StatusBarCountdown: View"))
    let menu = try #require(source.range(
        of: "private struct MenuContent: View",
        range: component.upperBound..<source.endIndex
    ))
    let componentBody = source[component.lowerBound..<menu.lowerBound]
    #expect(componentBody.contains("Text(text)"))
    #expect(componentBody.contains(".monospacedDigit()"))
    #expect(!componentBody.contains("Label("))
    #expect(!componentBody.contains("Image("))
}
