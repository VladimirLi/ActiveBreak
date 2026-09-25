import Foundation
import Testing

private func viewsSource() throws -> String {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repository.appendingPathComponent("Sources/ActiveBreak/Views.swift"),
        encoding: .utf8
    )
}

private func declaration(_ header: String, in source: String) throws -> Substring {
    let start = try #require(source.range(of: header))
    let rest = start.upperBound..<source.endIndex
    let next = [
        source.range(of: "\nprivate struct ", range: rest),
        source.range(of: "\nstruct ", range: rest),
        source.range(of: "\nprivate extension ", range: rest),
    ].compactMap { $0?.lowerBound }.min() ?? source.endIndex
    return source[start.lowerBound..<next]
}

@Test func dashboardOwnsValidatedDaySelectionAndDetailPanel() throws {
    let source = try viewsSource()
    let dashboard = try declaration("struct DashboardView: View", in: source)

    #expect(dashboard.contains("@State private var selectedDay: Date?"))
    #expect(dashboard.contains("DashboardDaySelection.resolve("))
    #expect(dashboard.contains(".onChange(of: dateRange)"))
    #expect(dashboard.contains("DayDetailPanel("))
    #expect(dashboard.contains("DashboardLayout.detailPanelWidth"))
    #expect(dashboard.contains("onSelectDay: { selectedDay = $0 }"))
    #expect(dashboard.contains("selectedDay: displayedDay"))
    #expect(dashboard.contains("MetricView("))

    let panel = try declaration("private struct DayDetailPanel: View", in: source)
    #expect(panel.contains("DashboardPresentation.dayTitle("))
    #expect(panel.contains("summary.activeDuration"))
    #expect(panel.contains("summary.overtimeDuration"))
    #expect(panel.contains("summary.longestCompletedStretch"))
    #expect(panel.contains("DashboardPresentation.mostActiveHourLabel("))
    #expect(panel.contains("DashboardPresentation.ongoingNote("))
}

@Test func everyDayIsOnePointerSelectableTargetWithSummaryRow() throws {
    let source = try viewsSource()
    let timeline = try declaration("private struct ActivityTimelineView: View", in: source)
    #expect(timeline.contains("TimelineDayView("))
    #expect(timeline.contains(".onKeyPress(.leftArrow)"))
    #expect(timeline.contains(".onKeyPress(.rightArrow)"))
    #expect(timeline.contains("DashboardDaySelection.moving("))
    #expect(timeline.contains("DashboardLayout.daySummaryHeight"))
    #expect(timeline.contains("ScrollViewReader"))
    #expect(timeline.contains("proxy.scrollTo(selectedDay)"))
    #expect(timeline.contains(".id(day.date)"))

    let day = try declaration("private struct TimelineDayView: View", in: source)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    let target = try #require(day.range(of: "Button { onSelectDay(day.date) } label: {"))
    let targetEnd = try #require(day.range(of: ".pointingHandCursor()", range: target.upperBound..<day.endIndex))
    let label = day[target.upperBound..<targetEnd.lowerBound]
    #expect(label.contains("DayHeaderView("))
    #expect(label.contains("TimelineDayBackground("))
    #expect(label.contains("DailySummaryView("))
    #expect(label.contains(".contentShape(Rectangle())"))
    #expect(day.contains(".accessibilityAddTraits(isSelected ? [.isSelected] : [])"))
    #expect(day.contains("DashboardPresentation.dayAccessibilityLabel("))
    #expect(day.contains("DashboardPresentation.dayAccessibilityValue("))
    #expect(day.contains(".onHover"))

    let segment = try #require(day.range(of: "ForEach(day.segments)"))
    let segmentBody = day[segment.lowerBound..<day.endIndex]
    let selectsDay = try #require(segmentBody.range(of: "onSelectDay(day.date)"))
    let showsPopover = try #require(segmentBody.range(of: "selectedSegment = segment"))
    #expect(selectsDay.lowerBound < showsPopover.lowerBound)

    let summary = try declaration("private struct DailySummaryView: View", in: source)
    #expect(summary.contains("DashboardPresentation.daySummaryLines("))
    #expect(summary.contains("DashboardLayout.daySummaryStyle("))

    let cursor = try declaration("private struct PointingHandCursor: ViewModifier", in: source)
    #expect(cursor.contains(".pointerStyle(.link)"))
    #expect(cursor.contains("NSCursor.pointingHand"))
}
