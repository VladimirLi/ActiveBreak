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
}

public struct DashboardSegmentFrame: Equatable, Sendable {
    public let y: Double
    public let height: Double
}

public enum DashboardLayout {
    public static let axisWidth: Double = 52

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
    public static func accessibilityLabel(
        for segment: DashboardSegment,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
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
                scale: scale
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
