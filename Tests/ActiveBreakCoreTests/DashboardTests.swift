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
    #expect(dashboard.scale.expandedStartMinute <= 120)
    #expect(dashboard.scale.expandedEndMinute >= 660)
    #expect(dashboard.days.allSatisfy { $0.scale == dashboard.scale })
    let alignedTenAM = dashboard.scale.position(for: 600)
    #expect(dashboard.days.allSatisfy { $0.scale.position(for: 600) == alignedTenAM })
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
        $0.endMinute <= segment.startMinute || $0.startMinute >= segment.endMinute
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
    #expect(dashboard.longestStretch == 0)
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
