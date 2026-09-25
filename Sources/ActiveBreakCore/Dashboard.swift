import Foundation

public enum DashboardRange: Int, CaseIterable, Identifiable, Sendable {
    case threeDays = 3
    case sevenDays = 7
    case fourteenDays = 14

    public static let `default`: Self = .sevenDays
    public var id: Int { rawValue }
    public var dayCount: Int { rawValue }
    public var title: String { "\(rawValue) days" }
}

public struct DashboardDateRange: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let range: DashboardRange

    public init(start: Date, end: Date, range: DashboardRange) {
        self.start = start
        self.end = end
        self.range = range
    }

    public init(
        range: DashboardRange = .default,
        endingAt endDate: Date,
        today: Date = .now,
        calendar: Calendar = .current
    ) {
        let lastDay = min(
            calendar.startOfDay(for: endDate),
            calendar.startOfDay(for: today)
        )
        start = calendar.date(byAdding: .day, value: 1 - range.dayCount, to: lastDay)!
        end = calendar.date(byAdding: .day, value: 1, to: lastDay)!
        self.range = range
    }

    public func shifted(
        by days: Int,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> DashboardDateRange {
        let currentLastDay = calendar.date(byAdding: .day, value: -1, to: end)!
        return DashboardDateRange(
            range: range,
            endingAt: calendar.date(byAdding: .day, value: days, to: currentLastDay)!,
            today: today,
            calendar: calendar
        )
    }

    public func canNavigateForward(
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        end < calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: today)
        )!
    }
}

public struct DashboardSegmentID: Hashable, Sendable {
    public let recordID: UUID
    public let start: Date
    public let end: Date
    public let isOvertime: Bool
    public let isOngoing: Bool
}

public struct DashboardSegment: Identifiable, Equatable, Sendable {
    public let id: DashboardSegmentID
    public let recordID: UUID
    public let start: Date
    public let end: Date
    public let isOvertime: Bool
    public let isOngoing: Bool
    public let startOffset: TimeInterval
    public let endOffset: TimeInterval

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public var typeLabel: String { isOvertime ? "Overtime" : "Active work" }

    init(
        recordID: UUID,
        start: Date,
        end: Date,
        isOvertime: Bool,
        isOngoing: Bool,
        startOffset: TimeInterval,
        endOffset: TimeInterval
    ) {
        id = DashboardSegmentID(
            recordID: recordID,
            start: start,
            end: end,
            isOvertime: isOvertime,
            isOngoing: isOngoing
        )
        self.recordID = recordID
        self.start = start
        self.end = end
        self.isOvertime = isOvertime
        self.isOngoing = isOngoing
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct DashboardTimeBand: Equatable, Sendable {
    public let startOffset: TimeInterval
    public let endOffset: TimeInterval
    public let isCompressed: Bool
}

public struct DashboardTimeScale: Equatable, Sendable {
    public let expandedStartOffset: TimeInterval
    public let expandedEndOffset: TimeInterval
    public let bands: [DashboardTimeBand]

    private static let compressedLength: TimeInterval = 24 * 60

    static func make(
        segments: [DashboardSegment],
        maximumDayDuration: TimeInterval
    ) -> DashboardTimeScale {
        let earliest = segments.map(\.startOffset).min() ?? 8 * 60 * 60
        let latest = segments.map(\.endOffset).max() ?? 18 * 60 * 60
        let expandedStart = max(0, floor(earliest / 3_600) * 3_600 - 3_600)
        let expandedEnd = min(
            maximumDayDuration,
            ceil(latest / 3_600) * 3_600 + 3_600
        )
        var bands: [DashboardTimeBand] = []
        if expandedStart > 0 {
            bands.append(DashboardTimeBand(
                startOffset: 0,
                endOffset: expandedStart,
                isCompressed: true
            ))
        }
        bands.append(DashboardTimeBand(
            startOffset: expandedStart,
            endOffset: expandedEnd,
            isCompressed: false
        ))
        if expandedEnd < maximumDayDuration {
            bands.append(DashboardTimeBand(
                startOffset: expandedEnd,
                endOffset: maximumDayDuration,
                isCompressed: true
            ))
        }
        return DashboardTimeScale(
            expandedStartOffset: expandedStart,
            expandedEndOffset: expandedEnd,
            bands: bands
        )
    }

    public func position(for offset: TimeInterval) -> Double {
        let maximum = bands.last?.endOffset ?? 0
        let clamped = min(max(0, offset), maximum)
        let total = bands.reduce(0) { $0 + displayLength($1) }
        guard total > 0 else { return 0 }
        var displayedOffset = 0.0
        for band in bands {
            let length = displayLength(band)
            if clamped <= band.endOffset {
                let fraction = band.endOffset == band.startOffset
                    ? 0
                    : (clamped - band.startOffset) / (band.endOffset - band.startOffset)
                return (displayedOffset + min(max(0, fraction), 1) * length) / total
            }
            displayedOffset += length
        }
        return 1
    }

    private func displayLength(_ band: DashboardTimeBand) -> TimeInterval {
        band.isCompressed ? Self.compressedLength : band.endOffset - band.startOffset
    }
}

public struct DashboardDay: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let duration: TimeInterval
    public let segments: [DashboardSegment]
    public let scale: DashboardTimeScale
    public let summary: DashboardDaySummary

    init(
        date: Date,
        duration: TimeInterval,
        segments: [DashboardSegment],
        scale: DashboardTimeScale,
        calendar: Calendar
    ) {
        self.date = date
        self.duration = duration
        self.segments = segments
        self.scale = scale
        summary = DashboardDaySummary.make(segments: segments, calendar: calendar)
    }

    public var isStandardLength: Bool { abs(duration - 86_400) <= 1 }

    func contains(_ instant: Date) -> Bool {
        date <= instant && instant < date.addingTimeInterval(duration)
    }
}

/// Per-day metrics derived from the same clipped segments the timeline draws.
public struct DashboardDaySummary: Equatable, Sendable {
    public let activeDuration: TimeInterval
    public let overtimeDuration: TimeInterval
    public let ongoingDuration: TimeInterval
    /// Longest completed record contribution within this day; ongoing work never counts.
    public let longestCompletedStretch: TimeInterval?
    /// Actual local hour with the most active time; ties choose the earlier hour.
    public let mostActiveHour: DateInterval?

    public static let empty = DashboardDaySummary(
        activeDuration: 0,
        overtimeDuration: 0,
        ongoingDuration: 0,
        longestCompletedStretch: nil,
        mostActiveHour: nil
    )

    public var hasOngoingWork: Bool { ongoingDuration > 0 }

    public init(
        activeDuration: TimeInterval,
        overtimeDuration: TimeInterval,
        ongoingDuration: TimeInterval,
        longestCompletedStretch: TimeInterval?,
        mostActiveHour: DateInterval?
    ) {
        self.activeDuration = activeDuration
        self.overtimeDuration = overtimeDuration
        self.ongoingDuration = ongoingDuration
        self.longestCompletedStretch = longestCompletedStretch
        self.mostActiveHour = mostActiveHour
    }

    static func make(segments: [DashboardSegment], calendar: Calendar) -> DashboardDaySummary {
        var completedByRecord: [UUID: TimeInterval] = [:]
        var durationByHour: [DateInterval: TimeInterval] = [:]
        for segment in segments {
            if !segment.isOngoing {
                completedByRecord[segment.recordID, default: 0] += segment.duration
            }
            var cursor = segment.start
            while cursor < segment.end {
                let hour = calendar.dateInterval(of: .hour, for: cursor)!
                let boundary = min(hour.end, segment.end)
                durationByHour[hour, default: 0] += boundary.timeIntervalSince(cursor)
                cursor = boundary
            }
        }
        let peak = durationByHour.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.start > rhs.key.start : lhs.value < rhs.value
        }
        return DashboardDaySummary(
            activeDuration: segments.reduce(0) { $0 + $1.duration },
            overtimeDuration: segments.filter(\.isOvertime).reduce(0) { $0 + $1.duration },
            ongoingDuration: segments.filter(\.isOngoing).reduce(0) { $0 + $1.duration },
            longestCompletedStretch: completedByRecord.values.max(),
            mostActiveHour: peak.flatMap { $0.value > 0 ? $0.key : nil }
        )
    }
}

public enum DashboardDaySelection {
    /// Keeps a visible selection; otherwise falls back to today, then the final visible day.
    public static func resolve(
        _ selection: Date?,
        in days: [DashboardDay],
        today: Date
    ) -> Date? {
        if let selection, let day = days.first(where: { $0.contains(selection) }) {
            return day.date
        }
        return days.first { $0.contains(today) }?.date ?? days.last?.date
    }

    public static func moving(
        _ selection: Date?,
        by offset: Int,
        in days: [DashboardDay],
        today: Date
    ) -> Date? {
        guard let current = resolve(selection, in: days, today: today),
              let index = days.firstIndex(where: { $0.date == current })
        else { return nil }
        return days[min(max(0, index + offset), days.count - 1)].date
    }
}

public enum DashboardDaySummaryStyle: Equatable, Sendable {
    case labeled
    case compact
}

public struct DashboardDaySummaryLines: Equatable, Sendable {
    public let active: String
    public let overtime: String

    public init(active: String, overtime: String) {
        self.active = active
        self.overtime = overtime
    }
}

public struct DashboardSegmentFrame: Equatable, Sendable {
    public let y: Double
    public let height: Double
}

public struct DashboardAxisTick: Equatable, Sendable {
    public let offset: TimeInterval
    public let date: Date
    public let label: String
}

public enum DashboardLayout {
    public enum HorizontalRegion: Equatable, Sendable {
        case pinned
        case horizontalScroll
    }

    public static let axisWidth: Double = 86
    public static let daySummaryHeight: Double = 40
    public static let detailPanelWidth: Double = 260
    public static let axisRegion: HorizontalRegion = .pinned
    public static let dayColumnsRegion: HorizontalRegion = .horizontalScroll

    public static func dayWidth(for range: DashboardRange) -> Double {
        switch range {
        case .threeDays:
            return 250
        case .sevenDays:
            return 128
        case .fourteenDays:
            return 72
        }
    }

    public static func daySummaryStyle(for range: DashboardRange) -> DashboardDaySummaryStyle {
        range == .threeDays ? .labeled : .compact
    }

    public static func scrollContentWidth(for range: DashboardRange) -> Double {
        dayWidth(for: range) * Double(range.dayCount)
    }

    public static func segmentFrame(
        _ segment: DashboardSegment,
        scale: DashboardTimeScale,
        height: Double
    ) -> DashboardSegmentFrame {
        let top = scale.position(for: segment.startOffset) * height
        let bottom = scale.position(for: segment.endOffset) * height
        return DashboardSegmentFrame(y: top, height: max(0, bottom - top))
    }
}

public enum DashboardPresentation {
    public static func axisReferenceDay(in days: [DashboardDay]) -> DashboardDay? {
        days.first { abs($0.duration - 86_400) > 1 } ?? days.last
    }

    public static func axisTicks(
        offsets: [TimeInterval],
        referenceDay: Date,
        calendar: Calendar = .current
    ) -> [DashboardAxisTick] {
        let day = calendar.startOfDay(for: referenceDay)
        let formatter = dateFormatter("HH:mm ZZZZZ", calendar: calendar)
        return offsets.map { offset in
            let date = day.addingTimeInterval(offset)
            return DashboardAxisTick(
                offset: offset,
                date: date,
                label: formatter.string(from: date)
            )
        }
    }

    public static func axisReferenceLabel(
        for day: Date,
        calendar: Calendar = .current
    ) -> String {
        "Local time\n\(dateFormatter("MMM d", calendar: calendar).string(from: day))"
    }

    public static func popoverTimestamp(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        dateFormatter("EEE, MMM d, HH:mm:ss ZZZZZ", calendar: calendar).string(from: date)
    }

    public static func summaryDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        if totalMinutes < 60 {
            return String(format: "%dm %02ds", totalMinutes, seconds)
        }
        return String(
            format: "%dh %02dm %02ds",
            totalMinutes / 60,
            totalMinutes % 60,
            seconds
        )
    }

    public static func accessibilityLabel(
        for segment: DashboardSegment,
        calendar: Calendar = .current
    ) -> String {
        let formatter = dateFormatter("yyyy-MM-dd HH:mm:ss ZZZZZ", calendar: calendar)
        return [
            segment.typeLabel,
            formatter.string(from: segment.start),
            "to \(formatter.string(from: segment.end))",
            "\(Int(segment.duration.rounded())) seconds",
            segment.isOngoing ? "ongoing" : "completed",
        ].joined(separator: ", ")
    }

    public static func accessibilityValue(for segment: DashboardSegment) -> String {
        "\(Int(segment.duration.rounded())) seconds, \(segment.isOngoing ? "ongoing" : "completed")"
    }

    public static func daySummaryLines(
        for summary: DashboardDaySummary,
        style: DashboardDaySummaryStyle
    ) -> DashboardDaySummaryLines {
        let active = summaryDuration(summary.activeDuration)
        let overtime = summaryDuration(summary.overtimeDuration)
        switch style {
        case .labeled:
            return DashboardDaySummaryLines(active: "\(active) active", overtime: "\(overtime) overtime")
        case .compact:
            return DashboardDaySummaryLines(active: active, overtime: "+\(overtime)")
        }
    }

    public static func dayTitle(for day: DashboardDay, calendar: Calendar = .current) -> String {
        dateFormatter("EEEE, MMM d, yyyy", calendar: calendar).string(from: day.date)
    }

    public static func dayLengthNote(for day: DashboardDay) -> String? {
        day.isStandardLength ? nil : "\(Int((day.duration / 3_600).rounded()))-hour day"
    }

    /// Adds UTC offsets on daylight-saving days so repeated or skipped hours stay unambiguous.
    public static func mostActiveHourLabel(
        for day: DashboardDay,
        calendar: Calendar = .current
    ) -> String? {
        guard let hour = day.summary.mostActiveHour else { return nil }
        let time = dateFormatter("HH:mm", calendar: calendar)
        guard !day.isStandardLength else {
            return "\(time.string(from: hour.start))-\(time.string(from: hour.end))"
        }
        let offset = dateFormatter("ZZZZZ", calendar: calendar)
        let startOffset = offset.string(from: hour.start)
        let endOffset = offset.string(from: hour.end)
        if startOffset == endOffset {
            return "\(time.string(from: hour.start))-\(time.string(from: hour.end)) \(startOffset)"
        }
        return "\(time.string(from: hour.start)) \(startOffset)-\(time.string(from: hour.end)) \(endOffset)"
    }

    public static func ongoingNote(for summary: DashboardDaySummary) -> String? {
        guard summary.hasOngoingWork else { return nil }
        return "Includes \(summaryDuration(summary.ongoingDuration)) of ongoing work, "
            + "not counted as a completed stretch."
    }

    public static func dayAccessibilityLabel(
        for day: DashboardDay,
        calendar: Calendar = .current
    ) -> String {
        [dayTitle(for: day, calendar: calendar), dayLengthNote(for: day)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    public static func dayAccessibilityValue(for day: DashboardDay) -> String {
        let summary = day.summary
        var parts = [
            "Active time \(Int(summary.activeDuration.rounded())) seconds",
            "overtime \(Int(summary.overtimeDuration.rounded())) seconds",
        ]
        if summary.hasOngoingWork {
            parts.append("includes \(Int(summary.ongoingDuration.rounded())) seconds ongoing")
        }
        return parts.joined(separator: ", ")
    }

    private static func dateFormatter(
        _ format: String,
        calendar: Calendar
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

public struct DashboardProjection: Equatable, Sendable {
    public let range: DashboardDateRange
    public let days: [DashboardDay]
    public let scale: DashboardTimeScale
    public let activeDuration: TimeInterval
    public let overtimeDuration: TimeInterval
    public let longestStretch: TimeInterval?
    public let mostActiveHour: Int?

    public static func make(
        records: [HistoryRecord],
        currentInterval: ActiveInterval? = nil,
        range: DashboardDateRange,
        calendar: Calendar = .current
    ) -> DashboardProjection {
        var dayStarts: [(date: Date, duration: TimeInterval)] = []
        var day = range.start
        while day < range.end {
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            dayStarts.append((day, next.timeIntervalSince(day)))
            day = next
        }

        var segmentsByDay: [Date: [DashboardSegment]] = [:]
        var durationByCompletedRecord: [UUID: TimeInterval] = [:]
        var hourlyDuration = Array(repeating: TimeInterval(0), count: 24)

        func project(
            id: UUID,
            segments: [TimeSegment],
            isOngoing: Bool,
            countsForLongest: Bool
        ) {
            for segment in segments {
                guard let clipped = clip(segment, from: range.start, before: range.end) else {
                    continue
                }
                for part in HistoryAggregator.split(clipped, calendar: calendar) {
                    let day = calendar.startOfDay(for: part.start)
                    let dashboardSegment = DashboardSegment(
                        recordID: id,
                        start: part.start,
                        end: part.end,
                        isOvertime: part.isOvertime,
                        isOngoing: isOngoing,
                        startOffset: part.start.timeIntervalSince(day),
                        endOffset: part.end.timeIntervalSince(day)
                    )
                    segmentsByDay[day, default: []].append(dashboardSegment)
                    if countsForLongest {
                        durationByCompletedRecord[id, default: 0] += part.duration
                    }
                    add(part, to: &hourlyDuration, calendar: calendar)
                }
            }
        }

        for record in records {
            project(
                id: record.id,
                segments: record.workSegments,
                isOngoing: false,
                countsForLongest: true
            )
        }
        let completedIDs = Set(records.map(\.id))
        if let currentInterval, !completedIDs.contains(currentInterval.id) {
            project(
                id: currentInterval.id,
                segments: currentInterval.workSegments,
                isOngoing: true,
                countsForLongest: false
            )
        }

        let allSegments = segmentsByDay.values.flatMap { $0 }
        let scale = DashboardTimeScale.make(
            segments: allSegments,
            maximumDayDuration: dayStarts.map(\.duration).max() ?? 24 * 60 * 60
        )
        let days = dayStarts.map { day in
            DashboardDay(
                date: day.date,
                duration: day.duration,
                segments: (segmentsByDay[day.date] ?? []).sorted {
                    $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
                },
                scale: scale,
                calendar: calendar
            )
        }

        return DashboardProjection(
            range: range,
            days: days,
            scale: scale,
            activeDuration: allSegments.reduce(0) { $0 + $1.duration },
            overtimeDuration: allSegments.filter(\.isOvertime).reduce(0) { $0 + $1.duration },
            longestStretch: durationByCompletedRecord.values.max(),
            mostActiveHour: hourlyDuration.max().flatMap { maximum in
                maximum > 0 ? hourlyDuration.firstIndex(of: maximum) : nil
            }
        )
    }

    private static func clip(
        _ segment: TimeSegment,
        from start: Date,
        before end: Date
    ) -> TimeSegment? {
        let clippedStart = max(segment.start, start)
        let clippedEnd = min(segment.end, end)
        guard clippedEnd > clippedStart else { return nil }
        return TimeSegment(
            start: clippedStart,
            end: clippedEnd,
            isOvertime: segment.isOvertime
        )
    }

    private static func add(
        _ segment: TimeSegment,
        to hourlyDuration: inout [TimeInterval],
        calendar: Calendar
    ) {
        var cursor = segment.start
        while cursor < segment.end {
            let hour = calendar.component(.hour, from: cursor)
            let boundary = min(calendar.dateInterval(of: .hour, for: cursor)!.end, segment.end)
            hourlyDuration[hour] += boundary.timeIntervalSince(cursor)
            cursor = boundary
        }
    }
}
