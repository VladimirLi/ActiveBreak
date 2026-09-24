import Foundation
import Testing
@testable import ActiveBreakCore

@Test func persistenceRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("history.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let data = PersistedData(
        settings: BreakSettings(workThreshold: 60),
        timer: TimerState(mode: .paused),
        history: [
            HistoryRecord(
                intervalStart: start,
                intervalEnd: start.addingTimeInterval(30),
                activeDuration: 30,
                overtimeDuration: 0
            ),
        ],
        savedAt: start
    )
    let store = HistoryStore(url: url)
    try store.save(data)
    #expect(try store.load() == data)
}

@Test func dailyAggregationSplitsAtLocalMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Stockholm"))
    let start = try #require(calendar.date(from: DateComponents(
        year: 2026, month: 1, day: 2, hour: 23, minute: 59
    )))
    let record = HistoryRecord(
        intervalStart: start,
        intervalEnd: start.addingTimeInterval(120),
        activeDuration: 120,
        overtimeDuration: 60,
        breakStart: start.addingTimeInterval(120),
        breakEnd: start.addingTimeInterval(240)
    )

    let summaries = HistoryAggregator.summarize([record], period: .daily, calendar: calendar)
    #expect(summaries.count == 2)
    #expect(abs(summaries[0].activeDuration - 60) < 0.001)
    #expect(abs(summaries[1].activeDuration - 60) < 0.001)
    #expect(summaries[1].breakCount == 1)
}

@Test func aggregationUsesProvidedCurrentTimezone() throws {
    let instant = Date(timeIntervalSince1970: 1_767_311_400)
    let record = HistoryRecord(
        intervalStart: instant,
        intervalEnd: instant.addingTimeInterval(1_200),
        activeDuration: 1_200,
        overtimeDuration: 0
    )
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

    #expect(HistoryAggregator.summarize([record], period: .daily, calendar: utc).count == 2)
    #expect(HistoryAggregator.summarize([record], period: .daily, calendar: newYork).count == 1)
}

@Test func exportFiltersDateRangeAndHasStableJSONSchema() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let included = HistoryRecord(
        intervalStart: start,
        intervalEnd: start.addingTimeInterval(60),
        activeDuration: 60,
        overtimeDuration: 10
    )
    let excluded = HistoryRecord(
        intervalStart: start.addingTimeInterval(1_000),
        intervalEnd: start.addingTimeInterval(1_060),
        activeDuration: 60,
        overtimeDuration: 0
    )
    let rangeEnd = start.addingTimeInterval(100)

    #expect(HistoryExporter.records([included, excluded], from: start, through: rangeEnd) == [included])
    let json = try HistoryExporter.json([included, excluded], from: start, through: rangeEnd)
    let object = try #require(JSONSerialization.jsonObject(with: json) as? [[String: Any]])
    #expect(object.count == 1)
    #expect(Set(object[0].keys) == [
        "id", "intervalStart", "intervalEnd", "activeDuration",
        "overtimeDuration", "breakStart", "breakEnd", "breakDuration",
    ])
}

@Test func csvSchemaRangeAndEscaping() throws {
    #expect(HistoryExporter.escape("plain") == "plain")
    #expect(HistoryExporter.escape("a,\"b\"") == "\"a,\"\"b\"\"\"")

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let record = HistoryRecord(
        intervalStart: start,
        intervalEnd: start.addingTimeInterval(60),
        activeDuration: 60,
        overtimeDuration: 10
    )
    let data = HistoryExporter.csv([record], from: start, through: start.addingTimeInterval(100))
    let csv = try #require(String(data: data, encoding: .utf8))
    #expect(csv.hasPrefix(
        "id,interval_start,interval_end,active_seconds,overtime_seconds,break_start,break_end,break_seconds\n"
    ))
    #expect(csv.split(separator: "\n").count == 2)
}

@Test func countdownFormatting() {
    #expect(CountdownFormatter.string(seconds: 65) == "01:05")
    #expect(CountdownFormatter.string(seconds: 3_600) == "1h 0m")
    #expect(CountdownFormatter.string(seconds: -5) == "-00:05")
}
