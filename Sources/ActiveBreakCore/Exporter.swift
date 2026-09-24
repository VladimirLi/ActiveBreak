import Foundation

public enum HistoryExporter {
    public static func records(
        _ records: [HistoryRecord],
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) -> [HistoryRecord] {
        records.flatMap { project($0, from: start, through: end, calendar: calendar) }
            .sorted {
                let left = min($0.intervalStart, $0.breakStart ?? $0.intervalStart)
                let right = min($1.intervalStart, $1.breakStart ?? $1.intervalStart)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }
    }

    public static func json(
        _ records: [HistoryRecord],
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) throws -> Data {
        try JSONEncoder.activeBreak.encode(Self.records(
            records,
            from: start,
            through: end,
            calendar: calendar
        ))
    }

    public static func csv(
        _ records: [HistoryRecord],
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) -> Data {
        let header = "id,interval_start,interval_end,active_seconds,overtime_seconds,break_start,break_end,break_seconds"
        let selected = Self.records(records, from: start, through: end, calendar: calendar)
        let rows = selected.map { record -> String in
            let values = [
                record.id.uuidString,
                record.intervalStart.ISO8601Format(),
                record.intervalEnd.ISO8601Format(),
                String(record.activeDuration),
                String(record.overtimeDuration),
                record.breakStart?.ISO8601Format() ?? "",
                record.breakEnd?.ISO8601Format() ?? "",
                String(record.breakDuration),
            ]
            return values.map(escape).joined(separator: ",")
        }
        return Data(([header] + rows).joined(separator: "\n").appending("\n").utf8)
    }

    public static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private struct Projection {
        var work: [TimeSegment] = []
        var breakSegment: TimeSegment?
        var intervalAnchor: Date?
    }

    private static func project(
        _ record: HistoryRecord,
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [HistoryRecord] {
        guard end >= start else { return [] }
        var days: [Date: Projection] = [:]

        for segment in record.workSegments {
            guard let clipped = clip(segment, from: start, through: end) else { continue }
            for part in HistoryAggregator.split(clipped, calendar: calendar) {
                days[calendar.startOfDay(for: part.start), default: Projection()].work.append(part)
            }
        }

        if let breakStart = record.breakStart,
           let breakEnd = record.breakEnd,
           let clipped = clip(TimeSegment(start: breakStart, end: breakEnd), from: start, through: end) {
            for part in HistoryAggregator.split(clipped, calendar: calendar) {
                days[calendar.startOfDay(for: part.start), default: Projection()].breakSegment = part
            }
        }

        if record.workSegments.isEmpty,
           record.intervalStart >= start,
           record.intervalStart <= end {
            let key = calendar.startOfDay(for: record.intervalStart)
            if days[key] == nil {
                days[key] = Projection(intervalAnchor: record.intervalStart)
            }
        }

        return days.values.map { projection in
            let firstWork = projection.work.first?.start
            let lastWork = projection.work.last?.end
            let fallback = projection.breakSegment?.start ?? projection.intervalAnchor ?? start
            return HistoryRecord(
                id: record.id,
                intervalStart: firstWork ?? fallback,
                intervalEnd: lastWork ?? firstWork ?? fallback,
                activeDuration: projection.work.reduce(0) { $0 + $1.duration },
                overtimeDuration: projection.work.filter(\.isOvertime).reduce(0) { $0 + $1.duration },
                breakStart: projection.breakSegment?.start,
                breakEnd: projection.breakSegment?.end,
                workSegments: projection.work
            )
        }
    }

    private static func clip(
        _ segment: TimeSegment,
        from start: Date,
        through end: Date
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
}
