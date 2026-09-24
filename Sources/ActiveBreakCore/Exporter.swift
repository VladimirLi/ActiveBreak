import Foundation

public enum HistoryExporter {
    public static func records(
        _ records: [HistoryRecord],
        from start: Date,
        through end: Date
    ) -> [HistoryRecord] {
        records.filter { record in
            let intervalOverlaps = record.intervalEnd >= start && record.intervalStart <= end
            let breakOverlaps = record.breakStart.map { breakStart in
                let breakEnd = record.breakEnd ?? breakStart
                return breakEnd >= start && breakStart <= end
            } ?? false
            return intervalOverlaps || breakOverlaps
        }
    }

    public static func json(
        _ records: [HistoryRecord],
        from start: Date,
        through end: Date
    ) throws -> Data {
        try JSONEncoder.activeBreak.encode(Self.records(records, from: start, through: end))
    }

    public static func csv(
        _ records: [HistoryRecord],
        from start: Date,
        through end: Date
    ) -> Data {
        let header = "id,interval_start,interval_end,active_seconds,overtime_seconds,break_start,break_end,break_seconds"
        let selected = Self.records(records, from: start, through: end)
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
}
