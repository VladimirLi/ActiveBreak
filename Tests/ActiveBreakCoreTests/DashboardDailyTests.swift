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

private func record(
    _ segments: [TimeSegment],
    id: UUID = UUID()
) -> HistoryRecord {
    HistoryRecord(
        id: id,
        intervalStart: segments.first!.start,
        intervalEnd: segments.last!.end,
        activeDuration: segments.reduce(0) { $0 + $1.duration },
        overtimeDuration: segments.filter(\.isOvertime).reduce(0) { $0 + $1.duration },
        workSegments: segments
    )
}

private let threeDays = DashboardDateRange(start: date(22), end: date(25), range: .threeDays)

@Test func daySummaryReportsExactPerDayMetricsFromTimelineSegments() throws {
    let morning = record([
        TimeSegment(start: date(22, hour: 10), end: date(22, hour: 10, minute: 50, second: 7)),
        TimeSegment(
            start: date(22, hour: 10, minute: 50, second: 7),
            end: date(22, hour: 11, minute: 5, second: 9),
            isOvertime: true
        ),
    ])
    let afternoon = record([
        TimeSegment(start: date(22, hour: 14, minute: 10), end: date(22, hour: 14, minute: 40)),
    ])
    let nextDay = record([
        TimeSegment(start: date(23, hour: 9), end: date(23, hour: 9, minute: 20, second: 1)),
    ])
    let dashboard = DashboardProjection.make(
        records: [morning, afternoon, nextDay],
        range: threeDays,
        calendar: utc
    )
    let first = dashboard.days[0].summary
    let second = dashboard.days[1].summary

    #expect(first.activeDuration == 3_909 + 1_800)
    #expect(first.overtimeDuration == 902)
    #expect(first.ongoingDuration == 0)
    #expect(!first.hasOngoingWork)
    #expect(first.longestCompletedStretch == 3_909)
    #expect(first.mostActiveHour == DateInterval(start: date(22, hour: 10), end: date(22, hour: 11)))
    #expect(second.activeDuration == 1_201)
    #expect(second.longestCompletedStretch == 1_201)
    #expect(second.mostActiveHour == DateInterval(start: date(23, hour: 9), end: date(23, hour: 10)))
    for day in dashboard.days {
        #expect(day.summary.activeDuration == day.segments.reduce(0) { $0 + $1.duration })
        #expect(day.summary.overtimeDuration
            == day.segments.filter(\.isOvertime).reduce(0) { $0 + $1.duration })
    }
    #expect(dashboard.days.reduce(0) { $0 + $1.summary.activeDuration } == dashboard.activeDuration)
    #expect(dashboard.days.reduce(0) { $0 + $1.summary.overtimeDuration } == dashboard.overtimeDuration)
}

@Test func daySummaryClipsAtMidnightAndRangeBoundaries() throws {
    let beforeRange = record([
        TimeSegment(start: date(21, hour: 23), end: date(22, hour: 0, minute: 40)),
    ])
    let acrossMidnight = record([
        TimeSegment(start: date(22, hour: 23, minute: 15), end: date(23, hour: 1)),
    ])
    let afterRange = record([
        TimeSegment(start: date(24, hour: 23, minute: 50), end: date(25, hour: 2), isOvertime: true),
    ])
    let dashboard = DashboardProjection.make(
        records: [beforeRange, acrossMidnight, afterRange],
        range: threeDays,
        calendar: utc
    )
    let summaries = dashboard.days.map(\.summary)

    #expect(summaries[0].activeDuration == 2_400 + 2_700)
    #expect(summaries[0].longestCompletedStretch == 2_700)
    #expect(summaries[0].mostActiveHour == DateInterval(start: date(22, hour: 23), end: date(23)))
    #expect(summaries[1].activeDuration == 3_600)
    #expect(summaries[1].longestCompletedStretch == 3_600)
    #expect(summaries[2].activeDuration == 600)
    #expect(summaries[2].overtimeDuration == 600)
    #expect(summaries[2].longestCompletedStretch == 600)
    #expect(summaries[2].mostActiveHour == DateInterval(start: date(24, hour: 23), end: date(25)))
}

@Test func daySummaryKeepsOngoingWorkOutOfCompletedLongestStretch() throws {
    let completed = record([
        TimeSegment(start: date(24, hour: 8), end: date(24, hour: 8, minute: 20)),
    ])
    let current = ActiveInterval(
        id: UUID(),
        startedAt: date(24, hour: 9),
        lastActivityAt: date(24, hour: 10, minute: 30),
        workSegments: [
            TimeSegment(start: date(24, hour: 9), end: date(24, hour: 10)),
            TimeSegment(start: date(24, hour: 10), end: date(24, hour: 10, minute: 30), isOvertime: true),
        ],
        settings: BreakSettings(workThreshold: 60 * 60)
    )
    let onlyOngoing = ActiveInterval(
        id: UUID(),
        startedAt: date(24, hour: 9),
        lastActivityAt: date(24, hour: 9, minute: 45),
        workSegments: [TimeSegment(start: date(24, hour: 9), end: date(24, hour: 9, minute: 45))],
        settings: BreakSettings()
    )

    let mixed = DashboardProjection.make(
        records: [completed],
        currentInterval: current,
        range: threeDays,
        calendar: utc
    ).days[2].summary
    #expect(mixed.activeDuration == 1_200 + 5_400)
    #expect(mixed.overtimeDuration == 1_800)
    #expect(mixed.ongoingDuration == 5_400)
    #expect(mixed.hasOngoingWork)
    #expect(mixed.longestCompletedStretch == 1_200)
    #expect(mixed.mostActiveHour == DateInterval(start: date(24, hour: 9), end: date(24, hour: 10)))

    let ongoing = DashboardProjection.make(
        records: [],
        currentInterval: onlyOngoing,
        range: threeDays,
        calendar: utc
    ).days[2].summary
    #expect(ongoing.activeDuration == 2_700)
    #expect(ongoing.ongoingDuration == 2_700)
    #expect(ongoing.longestCompletedStretch == nil)
    #expect(DashboardPresentation.ongoingNote(for: ongoing)
        == "Includes 45m 00s of ongoing work, not counted as a completed stretch.")
    #expect(DashboardPresentation.ongoingNote(for: mixed)
        == "Includes 1h 30m 00s of ongoing work, not counted as a completed stretch.")
    #expect(DashboardPresentation.ongoingNote(for: DashboardDaySummary.empty) == nil)
}

@Test func daySummaryMostActiveHourSplitsAcrossHoursAndPrefersEarlierTie() {
    let split = record([
        TimeSegment(start: date(22, hour: 10, minute: 30), end: date(22, hour: 11, minute: 30)),
        TimeSegment(start: date(22, hour: 13), end: date(22, hour: 13, minute: 30)),
    ])
    let dashboard = DashboardProjection.make(records: [split], range: threeDays, calendar: utc)

    #expect(dashboard.days[0].summary.mostActiveHour
        == DateInterval(start: date(22, hour: 10), end: date(22, hour: 11)))
    #expect(dashboard.days[0].summary.longestCompletedStretch == 5_400)
}

@Test func daySummaryHandlesSpringForwardAndRepeatedFallBackHours() throws {
    var stockholm = Calendar(identifier: .gregorian)
    stockholm.timeZone = try #require(TimeZone(identifier: "Europe/Stockholm"))
    let iso = ISO8601DateFormatter()

    let springStart = try #require(iso.date(from: "2026-03-29T01:30:00+01:00"))
    let springEnd = try #require(iso.date(from: "2026-03-29T03:30:00+02:00"))
    let springDay = stockholm.startOfDay(for: springStart)
    let spring = DashboardProjection.make(
        records: [record([TimeSegment(start: springStart, end: springEnd)])],
        range: DashboardDateRange(
            start: springDay,
            end: try #require(stockholm.date(byAdding: .day, value: 1, to: springDay)),
            range: .threeDays
        ),
        calendar: stockholm
    ).days[0]
    #expect(spring.summary.activeDuration == 3_600)
    #expect(spring.summary.longestCompletedStretch == 3_600)
    let springHour = try #require(spring.summary.mostActiveHour)
    #expect(springHour.start == iso.date(from: "2026-03-29T01:00:00+01:00"))
    #expect(DashboardPresentation.dayLengthNote(for: spring) == "23-hour day")
    #expect(DashboardPresentation.mostActiveHourLabel(for: spring, calendar: stockholm)
        == "01:00 +01:00-03:00 +02:00")

    let firstStart = try #require(iso.date(from: "2026-10-25T02:10:00+02:00"))
    let firstEnd = try #require(iso.date(from: "2026-10-25T02:30:00+02:00"))
    let secondStart = try #require(iso.date(from: "2026-10-25T02:05:00+01:00"))
    let secondEnd = try #require(iso.date(from: "2026-10-25T02:50:00+01:00"))
    let fallDay = stockholm.startOfDay(for: firstStart)
    let fall = DashboardProjection.make(
        records: [
            record([TimeSegment(start: firstStart, end: firstEnd)]),
            record([TimeSegment(start: secondStart, end: secondEnd)]),
        ],
        range: DashboardDateRange(
            start: fallDay,
            end: try #require(stockholm.date(byAdding: .day, value: 1, to: fallDay)),
            range: .threeDays
        ),
        calendar: stockholm
    ).days[0]
    #expect(abs(fall.duration - 25 * 3_600) < 0.001)
    #expect(fall.summary.activeDuration == 1_200 + 2_700)
    #expect(fall.summary.longestCompletedStretch == 2_700)
    let fallHour = try #require(fall.summary.mostActiveHour)
    #expect(fallHour.start == iso.date(from: "2026-10-25T02:00:00+01:00"))
    #expect(fallHour.duration == 3_600)
    #expect(DashboardPresentation.dayLengthNote(for: fall) == "25-hour day")
    #expect(DashboardPresentation.mostActiveHourLabel(for: fall, calendar: stockholm)
        == "02:00-03:00 +01:00")
}

@Test func emptyDaySummaryIsExplicitZeroState() throws {
    let dashboard = DashboardProjection.make(records: [], range: threeDays, calendar: utc)
    let day = dashboard.days[1]

    #expect(day.summary == DashboardDaySummary.empty)
    #expect(day.summary.activeDuration == 0)
    #expect(day.summary.overtimeDuration == 0)
    #expect(day.summary.longestCompletedStretch == nil)
    #expect(day.summary.mostActiveHour == nil)
    #expect(DashboardPresentation.mostActiveHourLabel(for: day, calendar: utc) == nil)
    #expect(DashboardPresentation.dayLengthNote(for: day) == nil)
    #expect(DashboardPresentation.daySummaryLines(for: day.summary, style: .labeled)
        == DashboardDaySummaryLines(active: "0s active", overtime: "0s overtime"))
    #expect(DashboardPresentation.daySummaryLines(for: day.summary, style: .compact)
        == DashboardDaySummaryLines(active: "0s", overtime: "+0s"))
    #expect(DashboardPresentation.dayAccessibilityValue(for: day)
        == "Active time 0 seconds, overtime 0 seconds")
}

@Test func allEmptyRangeStillProjectsSelectableZeroDays() throws {
    let today = date(24, hour: 12)
    let week = DashboardDateRange(range: .sevenDays, endingAt: today, today: today, calendar: utc)
    let dashboard = DashboardProjection.make(records: [], range: week, calendar: utc)

    #expect(!dashboard.hasActivity)
    #expect(dashboard.days.count == 7)
    #expect(dashboard.days.allSatisfy { $0.summary == .empty })
    #expect(DashboardPresentation.axisReferenceDay(in: dashboard.days) != nil)
    #expect(DashboardPresentation.emptyRangeNote(for: dashboard)
        == "No activity in this range. Select any day for its details.")
    #expect(DashboardDaySelection.resolve(nil, in: dashboard.days, today: today) == date(24))
    for day in dashboard.days {
        #expect(DashboardDaySelection.resolve(day.date, in: dashboard.days, today: today) == day.date)
        #expect(DashboardPresentation.daySummaryLines(for: day.summary, style: .compact)
            == DashboardDaySummaryLines(active: "0s", overtime: "+0s"))
        #expect(DashboardPresentation.mostActiveHourLabel(for: day, calendar: utc) == nil)
    }

    let active = DashboardProjection.make(
        records: [record([TimeSegment(start: date(20, hour: 9), end: date(20, hour: 9, second: 1))])],
        range: week,
        calendar: utc
    )
    #expect(active.hasActivity)
    #expect(DashboardPresentation.emptyRangeNote(for: active) == nil)
}

@Test func daySummaryLinesKeepExactSecondsForEveryRange() {
    let summary = DashboardDaySummary(
        activeDuration: 5 * 3_600 + 42 * 60 + 12,
        overtimeDuration: 32 * 60 + 10,
        ongoingDuration: 0,
        longestCompletedStretch: 3_600,
        mostActiveHour: nil
    )

    #expect(DashboardLayout.daySummaryStyle(for: .threeDays) == .labeled)
    #expect(DashboardLayout.daySummaryStyle(for: .sevenDays) == .compact)
    #expect(DashboardLayout.daySummaryStyle(for: .fourteenDays) == .compact)
    #expect(DashboardPresentation.daySummaryLines(for: summary, style: .labeled)
        == DashboardDaySummaryLines(active: "5h 42m 12s active", overtime: "32m 10s overtime"))
    #expect(DashboardPresentation.daySummaryLines(for: summary, style: .compact)
        == DashboardDaySummaryLines(active: "5h 42m 12s", overtime: "+32m 10s"))
    #expect(DashboardLayout.daySummaryHeight >= 36)
    #expect(DashboardLayout.detailPanelWidth >= 240)
}

@Test func dayPresentationNamesDateAndExactAccessibleValues() throws {
    let current = ActiveInterval(
        id: UUID(),
        startedAt: date(24, hour: 9),
        lastActivityAt: date(24, hour: 9, minute: 10),
        workSegments: [TimeSegment(start: date(24, hour: 9), end: date(24, hour: 9, minute: 10))],
        settings: BreakSettings()
    )
    let dashboard = DashboardProjection.make(
        records: [record([
            TimeSegment(start: date(24, hour: 7), end: date(24, hour: 7, minute: 30)),
            TimeSegment(start: date(24, hour: 7, minute: 30), end: date(24, hour: 7, minute: 35), isOvertime: true),
        ])],
        currentInterval: current,
        range: threeDays,
        calendar: utc
    )
    let day = dashboard.days[2]

    #expect(DashboardPresentation.dayTitle(for: day, calendar: utc) == "Thursday, Sep 24, 2026")
    #expect(DashboardPresentation.dayAccessibilityLabel(for: day, calendar: utc)
        == "Thursday, Sep 24, 2026")
    #expect(DashboardPresentation.dayAccessibilityValue(for: day)
        == "Active time 2700 seconds, overtime 300 seconds, includes 600 seconds ongoing")
    #expect(DashboardPresentation.mostActiveHourLabel(for: day, calendar: utc) == "07:00-08:00")
}

@Test func daySelectionInitializesToTodayOrFinalVisibleDay() throws {
    let days = DashboardProjection.make(records: [], range: threeDays, calendar: utc).days

    #expect(DashboardDaySelection.resolve(nil, in: days, today: date(23, hour: 15)) == date(23))
    #expect(DashboardDaySelection.resolve(nil, in: days, today: date(30, hour: 15)) == date(24))
    #expect(DashboardDaySelection.resolve(nil, in: [], today: date(23)) == nil)
}

@Test func daySelectionKeepsVisibleUserChoiceAndReplacesStaleDays() throws {
    let days = DashboardProjection.make(records: [], range: threeDays, calendar: utc).days

    #expect(DashboardDaySelection.resolve(date(22), in: days, today: date(24, hour: 9)) == date(22))
    #expect(DashboardDaySelection.resolve(date(22, hour: 18), in: days, today: date(24)) == date(22))
    #expect(DashboardDaySelection.resolve(date(10), in: days, today: date(24, hour: 9)) == date(24))
    #expect(DashboardDaySelection.resolve(date(10), in: days, today: date(23, hour: 9)) == date(23))
    #expect(DashboardDaySelection.resolve(date(28), in: days, today: date(30)) == date(24))
}

@Test func daySelectionFollowsRangeChangesAndNavigation() throws {
    let today = date(24, hour: 12)
    let week = DashboardDateRange(range: .sevenDays, endingAt: today, today: today, calendar: utc)
    let weekDays = DashboardProjection.make(records: [], range: week, calendar: utc).days
    let chosen = try #require(DashboardDaySelection.resolve(date(19), in: weekDays, today: today))
    #expect(chosen == date(19))

    let fortnight = DashboardDateRange(range: .fourteenDays, endingAt: today, today: today, calendar: utc)
    let fortnightDays = DashboardProjection.make(records: [], range: fortnight, calendar: utc).days
    #expect(DashboardDaySelection.resolve(chosen, in: fortnightDays, today: today) == date(19))

    let three = DashboardDateRange(range: .threeDays, endingAt: today, today: today, calendar: utc)
    let threeDaysVisible = DashboardProjection.make(records: [], range: three, calendar: utc).days
    #expect(DashboardDaySelection.resolve(chosen, in: threeDaysVisible, today: today) == date(24))

    let previous = week.shifted(by: -7, today: today, calendar: utc)
    let previousDays = DashboardProjection.make(records: [], range: previous, calendar: utc).days
    let fallback = DashboardDaySelection.resolve(chosen, in: previousDays, today: today)
    #expect(fallback == date(17))
    #expect(previousDays.contains { $0.date == fallback })
}

@Test func daySelectionMovesByKeyboardWithinVisibleDays() {
    let days = DashboardProjection.make(records: [], range: threeDays, calendar: utc).days

    #expect(DashboardDaySelection.moving(date(23), by: -1, in: days, today: date(24)) == date(22))
    #expect(DashboardDaySelection.moving(date(23), by: 1, in: days, today: date(24)) == date(24))
    #expect(DashboardDaySelection.moving(date(22), by: -1, in: days, today: date(24)) == date(22))
    #expect(DashboardDaySelection.moving(date(24), by: 1, in: days, today: date(24)) == date(24))
    #expect(DashboardDaySelection.moving(nil, by: -1, in: days, today: date(24)) == date(23))
    #expect(DashboardDaySelection.moving(nil, by: 1, in: [], today: date(24)) == nil)
}
