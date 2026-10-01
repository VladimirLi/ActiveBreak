import Foundation
import Testing

@Test func menuBarLabelIsTemplateGlyphBesideCountdown() throws {
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
    #expect(componentBody.contains("@ObservedObject var status: StatusBarModel"))
    #expect(componentBody.contains("Text(status.text)"))
    #expect(componentBody.contains(".monospacedDigit()"))
    #expect(!componentBody.contains("Label("))

    #expect(componentBody.contains("HStack(spacing: 5)"))
    #expect(componentBody.contains("NSImage(named: \"MenuBarGlyphTemplate\")"))
    #expect(componentBody.contains("image.isTemplate = true"))
    let glyph = try #require(componentBody.range(of: "Image(nsImage: glyph)"))
    let text = try #require(componentBody.range(of: "Text(status.text)"))
    #expect(glyph.lowerBound < text.lowerBound)
    let glyphBlock = componentBody[glyph.lowerBound..<text.lowerBound]
    #expect(!glyphBlock.contains("foregroundStyle"))
    #expect(!glyphBlock.contains("foregroundColor"))
    #expect(componentBody.contains(".foregroundStyle(status.isOverdue ? .red : .primary)"))
}

@Test func appBundleShipsIconAndMenuBarGlyph() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fileManager = FileManager.default
    for name in ["AppIcon.icns", "MenuBarGlyphTemplate.png", "MenuBarGlyphTemplate@2x.png"] {
        #expect(fileManager.fileExists(atPath: repository.appendingPathComponent("Resources/\(name)").path))
    }

    let package = try String(
        contentsOf: repository.appendingPathComponent("scripts/package-app.sh"),
        encoding: .utf8
    )
    #expect(package.contains("<key>CFBundleIconFile</key>"))
    #expect(package.contains("<string>AppIcon</string>"))
    #expect(package.contains("Resources/AppIcon.icns"))
    #expect(package.contains("Resources/MenuBarGlyphTemplate.png"))
    #expect(package.contains("Resources/MenuBarGlyphTemplate@2x.png"))
    #expect(!package.contains("entitlements"))
}
