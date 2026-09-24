import Foundation
import Testing

@Test func dashboardUsesTimelineRangeControlsPopoverAndHistoryActions() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repository.appendingPathComponent("Sources/ActiveBreak/Views.swift"),
        encoding: .utf8
    )
    let dashboardStart = try #require(source.range(of: "struct DashboardView: View"))
    let dashboard = source[dashboardStart.lowerBound..<source.endIndex]

    #expect(dashboard.contains("DashboardProjection.make"))
    #expect(dashboard.contains("ForEach(DashboardRange.allCases"))
    #expect(dashboard.contains("ActivityTimelineView("))
    #expect(dashboard.contains(".popover(item:"))
    #expect(dashboard.contains("model.export("))
    #expect(dashboard.contains("model.deleteAllHistory()"))
    #expect(!dashboard.contains("HistoryPeriod"))
    #expect(!dashboard.contains("Chart("))
    #expect(!dashboard.contains("Table("))
}
