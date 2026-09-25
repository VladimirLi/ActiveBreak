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
    // An all-empty range keeps the interactive timeline and panel; the cue never replaces them.
    #expect(!dashboard.contains("ContentUnavailableView("))
    #expect(!dashboard.contains("allSatisfy({ $0.segments.isEmpty })"))
    let cue = try #require(dashboard.range(of: "DashboardPresentation.emptyRangeNote("))
    let timeline = try #require(dashboard.range(of: "ActivityTimelineView("))
    #expect(cue.lowerBound < timeline.lowerBound)
    #expect(dashboard[cue.lowerBound..<timeline.lowerBound].contains(".allowsHitTesting(false)"))

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
    #expect(timeline.contains("TimelineKeyboardFocusHost(onMove: moveSelection)"))
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

@Test func timelineKeepsArrowKeyFocusWithoutNativeFocusRing() throws {
    let source = try viewsSource()
    let timeline = try declaration("private struct ActivityTimelineView: View", in: source)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")

    // focusEffectDisabled() propagates to descendants, so the calendar, days, and blocks must not
    // sit under it. Only a sibling background host carries focus, the disabled ring, and arrow keys.
    #expect(!timeline.contains(".focusable()"))
    #expect(!timeline.contains(".focusEffectDisabled()"))
    #expect(!timeline.contains(".onKeyPress("))
    let background = try #require(timeline.range(of: ".background { TimelineKeyboardFocusHost(onMove: moveSelection) }"))
    let calendar = try #require(timeline.range(of: "TimelineDayView("))
    #expect(calendar.lowerBound < background.lowerBound)

    let host = try declaration("private struct TimelineKeyboardFocusHost: View", in: source)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    #expect(host.contains(
        ".focusable() .focusEffectDisabled() .onKeyPress(.leftArrow) { onMove(-1) } "
            + ".onKeyPress(.rightArrow) { onMove(1) }"
    ))
    for descendant in ["TimelineDayView", "Button", "ViewBuilder", "content", "ScrollView"] {
        #expect(!host.contains(descendant))
    }
    #expect(source.components(separatedBy: ".focusEffectDisabled()").count == 2)

    let day = try declaration("private struct TimelineDayView: View", in: source)
    #expect(!day.contains("focusEffectDisabled"))
    #expect(day.contains(".strokeBorder(Color.accentColor, lineWidth: 2)"))
    #expect(day.contains(".accessibilityAddTraits(isSelected ? [.isSelected] : [])"))
}
