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
        let todayStart = calendar.startOfDay(for: today)
        let requestedEnd = calendar.startOfDay(for: endDate)
        let lastDay = min(requestedEnd, todayStart)
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
        let requested = calendar.date(byAdding: .day, value: days, to: currentLastDay)!
        return DashboardDateRange(
            range: range,
            endingAt: requested,
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
}

public struct DashboardSegment: Identifiable, Equatable, Sendable {
    public let id: DashboardSegmentID
    public let recordID: UUID
    public let start: Date
    public let end: Date
    public let isOvertime: Bool
    public let startMinute: Double
    public let endMinute: Double

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    init(
        recordID: UUID,
        start: Date,
        end: Date,
        isOvertime: Bool,
        startMinute: Double,
        endMinute: Double
    ) {
        id = DashboardSegmentID(
            recordID: recordID,
            start: start,
            end: end,
            isOvertime: isOvertime
        )
        self.recordID = recordID
        self.start = start
        self.end = end
        self.isOvertime = isOvertime
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

public struct DashboardTimeBand: Equatable, Sendable {
    public let startMinute: Double
    public let endMinute: Double
    public let isCompressed: Bool
}

public struct DashboardTimeScale: Equatable, Sendable {
    public let expandedStartMinute: Double
    public let expandedEndMinute: Double
    public let bands: [DashboardTimeBand]

    private static let compressedLength: Double = 24

    public static func make(segments: [DashboardSegment]) -> DashboardTimeScale {
        let earliest = segments.map(\.startMinute).min() ?? 8 * 60
        let latest = segments.map(\.endMinute).max() ?? 18 * 60
        let expandedStart = max(0, floor(earliest / 60) * 60 - 60)
        let expandedEnd = min(24 * 60, ceil(latest / 60) * 60 + 60)
        var bands: [DashboardTimeBand] = []
        if expandedStart > 0 {
            bands.append(DashboardTimeBand(
                startMinute: 0,
                endMinute: expandedStart,
                isCompressed: true
            ))
        }
        bands.append(DashboardTimeBand(
            startMinute: expandedStart,
            endMinute: expandedEnd,
            isCompressed: false
        ))
        if expandedEnd < 24 * 60 {
            bands.append(DashboardTimeBand(
                startMinute: expandedEnd,
                endMinute: 24 * 60,
                isCompressed: true
            ))
        }
        return DashboardTimeScale(
            expandedStartMinute: expandedStart,
            expandedEndMinute: expandedEnd,
            bands: bands
        )
    }

    public func position(for minute: Double) -> Double {
        let clamped = min(max(0, minute), 24 * 60)
        let total = bands.reduce(0) { $0 + displayLength($1) }
        guard total > 0 else { return 0 }
        var offset = 0.0
        for band in bands {
            let length = displayLength(band)
            if clamped <= band.endMinute {
                let fraction = band.endMinute == band.startMinute
                    ? 0
                    : (clamped - band.startMinute) / (band.endMinute - band.startMinute)
                return (offset + min(max(0, fraction), 1) * length) / total
            }
            offset += length
        }
        return 1
    }

    private func displayLength(_ band: DashboardTimeBand) -> Double {
        band.isCompressed ? Self.compressedLength : band.endMinute - band.startMinute
    }
}

public struct DashboardDay: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let segments: [DashboardSegment]
    public let scale: DashboardTimeScale
}

public struct DashboardProjection: Equatable, Sendable {
    public let range: DashboardDateRange
    public let days: [DashboardDay]
    public let scale: DashboardTimeScale
    public let activeDuration: TimeInterval
    public let overtimeDuration: TimeInterval
    public let longestStretch: TimeInterval
    public let mostActiveHour: Int?

    public static func make(
        records: [HistoryRecord],
        range: DashboardDateRange,
        calendar: Calendar = .current
    ) -> DashboardProjection {
        var segmentsByDay: [Date: [DashboardSegment]] = [:]
        var durationByRecord: [UUID: TimeInterval] = [:]
        var hourlyDuration = Array(repeating: TimeInterval(0), count: 24)

        for record in records {
            for segment in record.workSegments {
                guard let clipped = clip(segment, from: range.start, before: range.end) else {
                    continue
                }
                for part in HistoryAggregator.split(clipped, calendar: calendar) {
                    let day = calendar.startOfDay(for: part.start)
                    let dashboardSegment = DashboardSegment(
                        recordID: record.id,
                        start: part.start,
                        end: part.end,
                        isOvertime: part.isOvertime,
                        startMinute: minute(of: part.start, on: day, calendar: calendar),
                        endMinute: minute(of: part.end, on: day, calendar: calendar)
                    )
                    segmentsByDay[day, default: []].append(dashboardSegment)
                    durationByRecord[record.id, default: 0] += part.duration
                    add(part, to: &hourlyDuration, calendar: calendar)
                }
            }
        }

        let allSegments = segmentsByDay.values.flatMap { $0 }
        let scale = DashboardTimeScale.make(segments: allSegments)
        var days: [DashboardDay] = []
        var day = range.start
        while day < range.end {
            days.append(DashboardDay(
                date: day,
                segments: (segmentsByDay[day] ?? []).sorted {
                    $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
                },
                scale: scale
            ))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        return DashboardProjection(
            range: range,
            days: days,
            scale: scale,
            activeDuration: allSegments.reduce(0) { $0 + $1.duration },
            overtimeDuration: allSegments.filter(\.isOvertime).reduce(0) { $0 + $1.duration },
            longestStretch: durationByRecord.values.max() ?? 0,
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

    private static func minute(
        of date: Date,
        on day: Date,
        calendar: Calendar
    ) -> Double {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        if date >= nextDay { return 24 * 60 }
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return Double(components.hour ?? 0) * 60
            + Double(components.minute ?? 0)
            + Double(components.second ?? 0) / 60
            + Double(components.nanosecond ?? 0) / 60_000_000_000
    }

    private static func add(
        _ segment: TimeSegment,
        to hourlyDuration: inout [TimeInterval],
        calendar: Calendar
    ) {
        var cursor = segment.start
        while cursor < segment.end {
            let hour = calendar.component(.hour, from: cursor)
            let boundary = min(
                calendar.dateInterval(of: .hour, for: cursor)!.end,
                segment.end
            )
            hourlyDuration[hour] += boundary.timeIntervalSince(cursor)
            cursor = boundary
        }
    }
}
