import Foundation
import Testing
@testable import ActiveBreakCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func date(
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0
) -> Date {
    utc.date(from: DateComponents(
        year: 2026,
        month: 9,
        day: day,
        hour: hour,
        minute: minute,
        second: second
    ))!
}

@Test func dashboardRangesDefaultToSevenDaysAndUseCalendarBoundaries() {
    let today = date(24, hour: 15)

    #expect(DashboardRange.default == .sevenDays)
    #expect(DashboardRange.allCases.map(\.dayCount) == [3, 7, 14])
    #expect(DashboardDateRange(range: .threeDays, endingAt: today, today: today, calendar: utc)
        == DashboardDateRange(start: date(22), end: date(25), range: .threeDays))
    #expect(DashboardDateRange(range: .sevenDays, endingAt: today, today: today, calendar: utc)
        == DashboardDateRange(start: date(18), end: date(25), range: .sevenDays))
    #expect(DashboardDateRange(range: .fourteenDays, endingAt: today, today: today, calendar: utc)
        == DashboardDateRange(start: date(11), end: date(25), range: .fourteenDays))
}

@Test func dashboardNavigationNeverMovesPastToday() {
    let today = date(24, hour: 15)
    let current = DashboardDateRange(
        range: .sevenDays,
        endingAt: today,
        today: today,
        calendar: utc
    )
    let previous = current.shifted(by: -7, today: today, calendar: utc)
    let returned = previous.shifted(by: 7, today: today, calendar: utc)
    let clamped = current.shifted(by: 7, today: today, calendar: utc)

    #expect(current.canNavigateForward(today: today, calendar: utc) == false)
    #expect(previous.start == date(11))
    #expect(previous.end == date(18))
    #expect(previous.canNavigateForward(today: today, calendar: utc))
    #expect(returned == current)
    #expect(clamped == current)
}

@Test func dashboardProjectionClipsAtRangeAndMidnightAndPreservesClassification() throws {
    let record = HistoryRecord(
        intervalStart: date(17, hour: 23, minute: 30),
        intervalEnd: date(19, hour: 0, minute: 30),
        activeDuration: 7_200,
        overtimeDuration: 3_600,
        workSegments: [
            TimeSegment(start: date(17, hour: 23, minute: 30), end: date(18, hour: 0, minute: 30)),
            TimeSegment(
                start: date(18, hour: 23, minute: 30),
                end: date(19, hour: 0, minute: 30),
                isOvertime: true
            ),
        ]
    )
    let range = DashboardDateRange(start: date(18), end: date(19), range: .threeDays)
    let dashboard = DashboardProjection.make(records: [record], range: range, calendar: utc)
    let segments = dashboard.days.flatMap(\.segments)

    #expect(segments.count == 2)
    #expect(segments[0].start == date(18))
    #expect(segments[0].end == date(18, hour: 0, minute: 30))
    #expect(!segments[0].isOvertime)
    #expect(segments[1].start == date(18, hour: 23, minute: 30))
    #expect(segments[1].end == date(19))
    #expect(segments[1].isOvertime)
    #expect(dashboard.activeDuration == 3_600)
    #expect(dashboard.overtimeDuration == 1_800)
}

@Test func dashboardUsesOneScaleForEveryDayAndIncludesUnusualHours() throws {
    let early = HistoryRecord(
        intervalStart: date(22, hour: 2),
        intervalEnd: date(22, hour: 3),
        activeDuration: 3_600,
        overtimeDuration: 0
    )
    let daytime = HistoryRecord(
        intervalStart: date(23, hour: 10),
        intervalEnd: date(23, hour: 11),
        activeDuration: 3_600,
        overtimeDuration: 0
    )
    let range = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)
    let dashboard = DashboardProjection.make(records: [early, daytime], range: range, calendar: utc)

    #expect(dashboard.days.count == 3)
    #expect(dashboard.scale.expandedStartOffset <= 120 * 60)
    #expect(dashboard.scale.expandedEndOffset >= 660 * 60)
    #expect(dashboard.days.allSatisfy { $0.scale == dashboard.scale })
    let alignedTenAM = dashboard.scale.position(for: 10 * 60 * 60)
    #expect(dashboard.days.allSatisfy {
        $0.scale.position(for: 10 * 60 * 60) == alignedTenAM
    })
}

@Test func dashboardOnlyCompressesUniversallyEmptyTime() {
    let record = HistoryRecord(
        intervalStart: date(23, hour: 9, minute: 30),
        intervalEnd: date(23, hour: 17, minute: 15),
        activeDuration: 27_900,
        overtimeDuration: 0
    )
    let range = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)
    let dashboard = DashboardProjection.make(records: [record], range: range, calendar: utc)
    let segment = dashboard.days.flatMap(\.segments).first!

    #expect(dashboard.scale.bands.contains { $0.isCompressed })
    #expect(dashboard.scale.bands.filter { $0.isCompressed }.allSatisfy {
        $0.endOffset <= segment.startOffset || $0.startOffset >= segment.endOffset
    })
}

@Test func dashboardMetricsUseExactSegmentsLongestRecordAndEarlierPeakTie() {
    let first = HistoryRecord(
        intervalStart: date(22, hour: 10),
        intervalEnd: date(22, hour: 11, minute: 30),
        activeDuration: 5_400,
        overtimeDuration: 1_800,
        workSegments: [
            TimeSegment(start: date(22, hour: 10), end: date(22, hour: 11)),
            TimeSegment(
                start: date(22, hour: 11),
                end: date(22, hour: 11, minute: 30),
                isOvertime: true
            ),
        ]
    )
    let second = HistoryRecord(
        intervalStart: date(23, hour: 11, minute: 30),
        intervalEnd: date(23, hour: 12, minute: 30),
        activeDuration: 3_600,
        overtimeDuration: 0
    )
    let range = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)
    let dashboard = DashboardProjection.make(records: [first, second], range: range, calendar: utc)

    #expect(dashboard.activeDuration == 9_000)
    #expect(dashboard.overtimeDuration == 1_800)
    #expect(dashboard.longestStretch == 5_400)
    #expect(dashboard.mostActiveHour == 10)
}

@Test func dashboardMostActiveHourIsNilWithoutData() {
    let range = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)
    let dashboard = DashboardProjection.make(records: [], range: range, calendar: utc)

    #expect(dashboard.mostActiveHour == nil)
    #expect(dashboard.activeDuration == 0)
    #expect(dashboard.longestStretch == nil)
}

@Test func dashboardSegmentCarriesExactPopoverDetails() throws {
    let start = date(23, hour: 13, minute: 5, second: 30)
    let end = date(23, hour: 13, minute: 47, second: 15)
    let record = HistoryRecord(
        intervalStart: start,
        intervalEnd: end,
        activeDuration: end.timeIntervalSince(start),
        overtimeDuration: end.timeIntervalSince(start),
        workSegments: [TimeSegment(start: start, end: end, isOvertime: true)]
    )
    let range = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)
    let segment = try #require(
        DashboardProjection.make(records: [record], range: range, calendar: utc)
            .days.flatMap(\.segments).first
    )

    #expect(segment.recordID == record.id)
    #expect(segment.start == start)
    #expect(segment.end == end)
    #expect(segment.duration == end.timeIntervalSince(start))
    #expect(segment.isOvertime)
}

@Test func dashboardIncludesValidatedCurrentIntervalWithoutProvisionalTime() throws {
    let start = date(24, hour: 9)
    let current = ActiveInterval(
        id: UUID(),
        startedAt: start,
        lastActivityAt: date(24, hour: 10),
        workSegments: [
            TimeSegment(start: start, end: date(24, hour: 9, minute: 45)),
            TimeSegment(
                start: date(24, hour: 9, minute: 45),
                end: date(24, hour: 10),
                isOvertime: true
            ),
        ],
        settings: BreakSettings(workThreshold: 45 * 60)
    )
    let range = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)
    let dashboard = DashboardProjection.make(
        records: [],
        currentInterval: current,
        range: range,
        calendar: utc
    )
    let segments = dashboard.days.flatMap(\.segments)

    #expect(segments.count == 2)
    #expect(segments.allSatisfy { $0.isOngoing })
    #expect(dashboard.activeDuration == 3_600)
    #expect(dashboard.overtimeDuration == 900)
    #expect(dashboard.longestStretch == nil)
    #expect(segments.map(\.end).max() == current.lastActivityAt)
}

@Test func dashboardDoesNotDuplicateCurrentIntervalAfterClosure() {
    let id = UUID()
    let start = date(24, hour: 9)
    let segment = TimeSegment(start: start, end: date(24, hour: 10))
    let record = HistoryRecord(
        id: id,
        intervalStart: start,
        intervalEnd: segment.end,
        activeDuration: segment.duration,
        overtimeDuration: 0,
        workSegments: [segment]
    )
    let staleCurrent = ActiveInterval(
        id: id,
        startedAt: start,
        lastActivityAt: segment.end,
        workSegments: [segment],
        settings: BreakSettings()
    )
    let range = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)
    let dashboard = DashboardProjection.make(
        records: [record],
        currentInterval: staleCurrent,
        range: range,
        calendar: utc
    )

    #expect(dashboard.days.flatMap(\.segments).count == 1)
    #expect(dashboard.activeDuration == 3_600)
    #expect(dashboard.days.flatMap(\.segments).allSatisfy { !$0.isOngoing })
}

@Test func springForwardUsesExactElapsedDurationWithoutStretching() throws {
    var stockholm = Calendar(identifier: .gregorian)
    stockholm.timeZone = try #require(TimeZone(identifier: "Europe/Stockholm"))
    let start = try #require(ISO8601DateFormatter().date(from: "2026-03-29T01:30:00+01:00"))
    let end = try #require(ISO8601DateFormatter().date(from: "2026-03-29T03:30:00+02:00"))
    let day = stockholm.startOfDay(for: start)
    let range = DashboardDateRange(
        start: day,
        end: try #require(stockholm.date(byAdding: .day, value: 1, to: day)),
        range: .threeDays
    )
    let record = HistoryRecord(
        intervalStart: start,
        intervalEnd: end,
        activeDuration: 3_600,
        overtimeDuration: 0,
        workSegments: [TimeSegment(start: start, end: end)]
    )
    let segment = try #require(
        DashboardProjection.make(records: [record], range: range, calendar: stockholm)
            .days.flatMap(\.segments).first
    )

    let dayDuration = try #require(
        DashboardProjection.make(records: [record], range: range, calendar: stockholm)
            .days.first?.duration
    )
    #expect(abs(dayDuration - 23 * 3_600) < 0.001)
    #expect(segment.duration == 3_600)
    #expect(segment.endOffset - segment.startOffset == 3_600)
}

@Test func fallBackRepeatedHourKeepsDistinctOrderedGeometry() throws {
    var stockholm = Calendar(identifier: .gregorian)
    stockholm.timeZone = try #require(TimeZone(identifier: "Europe/Stockholm"))
    let firstStart = try #require(ISO8601DateFormatter().date(from: "2026-10-25T02:10:00+02:00"))
    let firstEnd = try #require(ISO8601DateFormatter().date(from: "2026-10-25T02:40:00+02:00"))
    let secondStart = try #require(ISO8601DateFormatter().date(from: "2026-10-25T02:10:00+01:00"))
    let secondEnd = try #require(ISO8601DateFormatter().date(from: "2026-10-25T02:40:00+01:00"))
    let day = stockholm.startOfDay(for: firstStart)
    let range = DashboardDateRange(
        start: day,
        end: try #require(stockholm.date(byAdding: .day, value: 1, to: day)),
        range: .threeDays
    )
    let records = [
        HistoryRecord(
            intervalStart: firstStart,
            intervalEnd: firstEnd,
            activeDuration: 1_800,
            overtimeDuration: 0,
            workSegments: [TimeSegment(start: firstStart, end: firstEnd)]
        ),
        HistoryRecord(
            intervalStart: secondStart,
            intervalEnd: secondEnd,
            activeDuration: 1_800,
            overtimeDuration: 0,
            workSegments: [TimeSegment(start: secondStart, end: secondEnd)]
        ),
    ]
    let dashboard = DashboardProjection.make(records: records, range: range, calendar: stockholm)
    let segments = dashboard.days.flatMap(\.segments)
    let firstFrame = DashboardLayout.segmentFrame(
        segments[0],
        scale: dashboard.scale,
        height: 350
    )
    let secondFrame = DashboardLayout.segmentFrame(
        segments[1],
        scale: dashboard.scale,
        height: 350
    )

    #expect(abs(try #require(dashboard.days.first?.duration) - 25 * 3_600) < 0.001)
    #expect(segments[0].startOffset < segments[1].startOffset)
    #expect(segments[0].endOffset <= segments[1].startOffset)
    #expect(abs(firstFrame.height - secondFrame.height) < 0.001)
    #expect(firstFrame.y < secondFrame.y)
    let firstLabel = DashboardPresentation.accessibilityLabel(
        for: segments[0],
        calendar: stockholm
    )
    let secondLabel = DashboardPresentation.accessibilityLabel(
        for: segments[1],
        calendar: stockholm
    )
    #expect(firstLabel.contains("+02:00"))
    #expect(secondLabel.contains("+01:00"))
    #expect(firstLabel != secondLabel)
}

@Test func dashboardLayoutKeepsAxisPinnedAndOnlyDaysScrollable() {
    #expect(DashboardLayout.axisWidth == 52)
    #expect(DashboardLayout.dayWidth(for: .threeDays) == 250)
    #expect(DashboardLayout.dayWidth(for: .sevenDays) == 128)
    #expect(DashboardLayout.dayWidth(for: .fourteenDays) == 72)
    #expect(DashboardLayout.scrollContentWidth(for: .fourteenDays) == 14 * 72)
    #expect(DashboardLayout.scrollContentWidth(for: .fourteenDays) > 760 - DashboardLayout.axisWidth)
}

@Test func dashboardPresentationNamesTypeAndUniqueAccessibleDetails() throws {
    let start = date(23, hour: 13, minute: 5, second: 30)
    let end = date(23, hour: 13, minute: 47, second: 15)
    let regular = try #require(projectedSegment(start: start, end: end, overtime: false))
    let overtime = try #require(projectedSegment(start: start, end: end, overtime: true))

    #expect(regular.typeLabel == "Active work")
    #expect(overtime.typeLabel == "Overtime")
    let regularLabel = DashboardPresentation.accessibilityLabel(
        for: regular,
        calendar: utc
    )
    let overtimeLabel = DashboardPresentation.accessibilityLabel(
        for: overtime,
        calendar: utc
    )
    #expect(regularLabel.contains("2026-09-23"))
    #expect(regularLabel.contains("13:05:30"))
    #expect(regularLabel.contains("13:47:15"))
    #expect(regularLabel.contains("2505 seconds"))
    #expect(regularLabel.contains("Active work"))
    #expect(overtimeLabel.contains("Overtime"))
    #expect(regularLabel != overtimeLabel)
    #expect(DashboardPresentation.accessibilityValue(for: regular)
        == "2505 seconds, completed")
}

private func projectedSegment(
    start: Date,
    end: Date,
    overtime: Bool
) -> DashboardSegment? {
    let record = HistoryRecord(
        intervalStart: start,
        intervalEnd: end,
        activeDuration: end.timeIntervalSince(start),
        overtimeDuration: overtime ? end.timeIntervalSince(start) : 0,
        workSegments: [TimeSegment(start: start, end: end, isOvertime: overtime)]
    )
    let range = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)
    return DashboardProjection.make(records: [record], range: range, calendar: utc)
        .days.flatMap(\.segments).first
}
