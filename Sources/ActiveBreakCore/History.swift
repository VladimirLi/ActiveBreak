import Foundation

public struct HistoryStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> PersistedData {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PersistedData()
        }
        return try JSONDecoder.activeBreak.decode(PersistedData.self, from: Data(contentsOf: url))
    }

    public func save(_ data: PersistedData) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.activeBreak.encode(data).write(to: url, options: .atomic)
    }
}

public enum HistoryPeriod: String, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
}

public struct HistorySummary: Identifiable, Equatable, Sendable {
    public var id: Date { start }
    public let start: Date
    public var activeDuration: TimeInterval
    public var overtimeDuration: TimeInterval
    public var breakCount: Int
    public var intervalCount: Int

    public var averageInterval: TimeInterval {
        intervalCount == 0 ? 0 : activeDuration / Double(intervalCount)
    }
}

public enum HistoryAggregator {
    public static func summarize(
        _ records: [HistoryRecord],
        period: HistoryPeriod,
        calendar: Calendar = .current
    ) -> [HistorySummary] {
        var summaries: [Date: HistorySummary] = [:]
        for record in records {
            for segment in split(record: record, calendar: calendar) {
                let key = bucket(for: segment.start, period: period, calendar: calendar)
                var summary = summaries[key] ?? HistorySummary(
                    start: key,
                    activeDuration: 0,
                    overtimeDuration: 0,
                    breakCount: 0,
                    intervalCount: 0
                )
                summary.activeDuration += segment.active
                summary.overtimeDuration += segment.overtime
                summary.breakCount += segment.breakCount
                summary.intervalCount += segment.intervalCount
                summaries[key] = summary
            }
        }
        return summaries.values.sorted { $0.start < $1.start }
    }

    private struct Segment {
        let start: Date
        let active: TimeInterval
        let overtime: TimeInterval
        let breakCount: Int
        let intervalCount: Int
    }

    private static func split(record: HistoryRecord, calendar: Calendar) -> [Segment] {
        var result: [Segment] = []
        let intervalSpan = max(0, record.intervalEnd.timeIntervalSince(record.intervalStart))
        for range in midnightRanges(from: record.intervalStart, to: record.intervalEnd, calendar: calendar) {
            let ratio = intervalSpan == 0 ? 1 : range.duration / intervalSpan
            result.append(Segment(
                start: range.start,
                active: record.activeDuration * ratio,
                overtime: record.overtimeDuration * ratio,
                breakCount: 0,
                intervalCount: 1
            ))
        }

        if let breakStart = record.breakStart, let breakEnd = record.breakEnd {
            for (index, range) in midnightRanges(from: breakStart, to: breakEnd, calendar: calendar).enumerated() {
                result.append(Segment(
                    start: range.start,
                    active: 0,
                    overtime: 0,
                    breakCount: index == 0 ? 1 : 0,
                    intervalCount: 0
                ))
            }
        }
        return result
    }

    private static func midnightRanges(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [Range<Date>] {
        guard end >= start else { return [] }
        if end == start {
            return [start..<start.addingTimeInterval(0.000_001)]
        }
        var ranges: [Range<Date>] = []
        var cursor = start
        while cursor < end {
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!
            let boundary = min(next, end)
            ranges.append(cursor..<boundary)
            cursor = boundary
        }
        return ranges
    }

    private static func bucket(
        for date: Date,
        period: HistoryPeriod,
        calendar: Calendar
    ) -> Date {
        switch period {
        case .daily:
            return calendar.startOfDay(for: date)
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: date)!.start
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)!.start
        }
    }
}

private extension Range where Bound == Date {
    var duration: TimeInterval { upperBound.timeIntervalSince(lowerBound) }
    var start: Date { lowerBound }
}

public extension JSONEncoder {
    static var activeBreak: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var activeBreak: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
