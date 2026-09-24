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
    #expect(dashboard.contains("currentInterval: model.currentInterval"))
    #expect(dashboard.contains("ForEach(DashboardRange.allCases"))
    #expect(dashboard.contains("ActivityTimelineView("))
    #expect(dashboard.contains(".popover(item:"))
    #expect(dashboard.contains("segment.typeLabel"))
    #expect(dashboard.contains("DashboardPresentation.accessibilityLabel("))
    #expect(dashboard.contains("DashboardPresentation.axisTicks("))
    #expect(dashboard.contains("DashboardPresentation.popoverTimestamp("))
    let timelineStart = try #require(dashboard.range(of: "private struct ActivityTimelineView"))
    let timeline = dashboard[timelineStart.lowerBound..<dashboard.endIndex]
    let axis = try #require(timeline.range(of: "TimelineAxis("))
    let scroller = try #require(timeline.range(of: "ScrollView(.horizontal)"))
    #expect(axis.lowerBound < scroller.lowerBound)
    #expect(dashboard.contains("model.export("))
    #expect(dashboard.contains("model.deleteAllHistory()"))
    #expect(!dashboard.contains("HistoryPeriod"))
    #expect(!dashboard.contains("Chart("))
    #expect(!dashboard.contains("Table("))
}
