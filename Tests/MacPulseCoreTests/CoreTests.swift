import XCTest
@testable import MacPulseCore

final class CoreTests: XCTestCase {
    var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    func testCrossMidnightAggregationDoesNotDoubleCount() {
        let midnight = Date(timeIntervalSince1970: 1_700_006_400)
        let record = ActivityRecord(bundleID: "test", appName: "Test", start: midnight.addingTimeInterval(-600), end: midnight.addingTimeInterval(1200))
        XCTAssertEqual(record.overlap(from: midnight.addingTimeInterval(-86400), to: midnight), 600)
        XCTAssertEqual(record.overlap(from: midnight, to: midnight.addingTimeInterval(86400)), 1200)
        XCTAssertEqual(record.overlap(from: midnight.addingTimeInterval(3600), to: midnight.addingTimeInterval(7200)), 0)
    }
    func testWeeklyTotalsAndRanking() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let records = DemoData.activity(now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let apps = Analytics.applications(records, from: today, to: today.addingTimeInterval(86400))
        XCTAssertEqual(apps.count, 4)
        XCTAssertEqual(apps.first?.name, "Xcode")
        XCTAssertEqual(apps.reduce(0) { $0 + $1.seconds }, 402 * 60)
        let days = Analytics.days(records, ending: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.seconds, 402 * 60)
        XCTAssertEqual(Analytics.days(records, ending: now, count: 0).count, 0)
    }
    func testClockIgnoresIdleDisabledExcludedAndSleepGaps() {
        var clock = ActivityClock()
        let t = Date(timeIntervalSince1970: 1000)
        func tick(_ offset: Double, enabled: Bool = true, idle: Double = 0, excluded: Bool = false) -> ActivityRecord? {
            clock.tick(at: t.addingTimeInterval(offset), bundleID: "test", name: "Test", category: .development, enabled: enabled, idleSeconds: idle, excluded: excluded)
        }
        XCTAssertNil(tick(0)); XCTAssertEqual(tick(5)?.duration, 5)
        XCTAssertNil(tick(10, idle: 65)); XCTAssertNil(tick(15)); XCTAssertEqual(tick(20)?.duration, 5)
        XCTAssertNil(tick(25, enabled: false)); XCTAssertNil(tick(30)); XCTAssertEqual(tick(35)?.duration, 5)
        XCTAssertEqual(tick(40, excluded: true)?.duration, 5); XCTAssertNil(tick(45)); XCTAssertEqual(tick(50)?.duration, 5)
        XCTAssertNil(tick(1000)); XCTAssertEqual(tick(1005)?.duration, 5)
        clock.reset(); XCTAssertNil(tick(1010))
    }
    func testAppSwitchAccountsPreviousApp() {
        var clock = ActivityClock(); let t = Date()
        _ = clock.tick(at: t, bundleID: "one", name: "One", category: .development, enabled: true, idleSeconds: 0, excluded: false)
        let old = clock.tick(at: t.addingTimeInterval(3), bundleID: "two", name: "Two", category: .music, enabled: true, idleSeconds: 0, excluded: false)
        XCTAssertEqual(old?.bundleID, "one")
        let next = clock.tick(at: t.addingTimeInterval(8), bundleID: "two", name: "Two", category: .music, enabled: true, idleSeconds: 0, excluded: false)
        XCTAssertEqual(next?.bundleID, "two"); XCTAssertEqual(next?.duration, 5)
    }
    func testDatabasePersistenceUpsertRetentionAndDeletion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("activity.sqlite")
        let date = Date(timeIntervalSince1970: 1000)
        var record = ActivityRecord(bundleID: "test", appName: "Quotes \" App", start: date, end: date.addingTimeInterval(5))
        let session = CodexSession(id: "a", date: date, lastEvent: date.addingTimeInterval(100), project: "MacPulse")
        do {
            let db = try Database(url: url); try db.save(record)
            record.end = date.addingTimeInterval(10); try db.save(record)
            try db.saveCodex([session]); XCTAssertEqual(try db.load().count, 1)
        }
        let reopened = try Database(url: url)
        XCTAssertEqual(try reopened.load(), [record]); XCTAssertEqual(try reopened.loadCodex(), [session])
        try reopened.prune(before: date.addingTimeInterval(20)); XCTAssertTrue(try reopened.load().isEmpty)
        XCTAssertEqual(try reopened.loadCodex().count, 1)
        try reopened.deleteAll(); XCTAssertTrue(try reopened.loadCodex().isEmpty)
    }
    func testDemoClockNeverWritesLiveHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try Database(url: folder.appendingPathComponent("test.sqlite"))
        var clock = ActivityClock()
        let start = Date()
        for offset in [0.0, 5, 10] {
            if let record = clock.tick(at: start.addingTimeInterval(offset), bundleID: "demo", name: "Demo", category: .other, enabled: true, idleSeconds: 0, excluded: false, demo: true) { try db.save(record) }
        }
        XCTAssertTrue(try db.load().isEmpty)
        XCTAssertNil(clock.tick(at: start.addingTimeInterval(15), bundleID: "live", name: "Live", category: .other, enabled: true, idleSeconds: 0, excluded: false, demo: false))
        let record = try XCTUnwrap(clock.tick(at: start.addingTimeInterval(20), bundleID: "live", name: "Live", category: .other, enabled: true, idleSeconds: 0, excluded: false, demo: false))
        try db.save(record)
        XCTAssertEqual(try db.load().map(\.bundleID), ["live"])
        XCTAssertEqual(try db.load().first?.duration, 5)
    }
    func testCSVQuotesAndFormulaSafety() {
        let record = ActivityRecord(bundleID: "test", appName: "=cmd,\"quoted\"", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 10))
        let csv = Analytics.csv([record])
        XCTAssertTrue(csv.contains("\"'=cmd,\"\"quoted\"\"\"")); XCTAssertTrue(csv.contains(",10,"))
        XCTAssertEqual(csv.components(separatedBy: "\n").count, 3)
    }
    func testNotchInteractions() {
        var interaction = NotchInteraction()
        interaction.enter(hoverEnabled: false); XCTAssertEqual(interaction.state, .collapsed)
        interaction.enter(hoverEnabled: true); XCTAssertEqual(interaction.state, .hover)
        interaction.leave(); XCTAssertEqual(interaction.state, .collapsed)
        interaction.click(); XCTAssertEqual(interaction.state, .expanded)
        interaction.leave(); XCTAssertEqual(interaction.state, .expanded)
        interaction.enter(hoverEnabled: true); XCTAssertEqual(interaction.state, .expanded)
        interaction.dismiss(); XCTAssertEqual(interaction.state, .collapsed)
        interaction.click(); interaction.click(); XCTAssertEqual(interaction.state, .collapsed)
    }
    func testCodexParserIgnoresContentAndHandlesPartialLines() throws {
        let lines = [
            #"{"timestamp":"2026-01-01T12:00:00.000Z","type":"session_meta","payload":{"id":"session-a","cwd":"/Users/private/Projects/MacPulse"}}"#,
            #"{"timestamp":"2026-01-01T12:05:00Z","type":"response_item","payload":{"content":"sensitive prompt"}}"#,
            "partial invalid json",
            #"{"timestamp":"2026-01-01T12:10:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120,"output_tokens":40}}}}"#
        ]
        let session = try XCTUnwrap(CodexParser.parse(lines: lines))
        XCTAssertEqual(session.project, "MacPulse"); XCTAssertEqual(session.duration, 600)
        XCTAssertEqual(session.inputTokens, 120); XCTAssertEqual(session.outputTokens, 40)
        let stored = String(data: try JSONEncoder().encode(session), encoding: .utf8)!
        XCTAssertFalse(stored.contains("sensitive")); XCTAssertFalse(stored.contains("/Users"))
        XCTAssertNil(CodexParser.parse(lines: ["broken"]))
    }
    func testPersistentSamplesEventsAndRetention() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.sqlite")
        let old = Date(timeIntervalSince1970: 1000)
        let new = old.addingTimeInterval(100)
        let sample = SystemSample(date: old, cpu: 0.2, memoryRatio: 0.4)
        let event = SessionEvent(date: new, kind: "Wake")
        do { let db = try Database(url: url); try db.saveSample(sample); try db.saveEvent(event) }
        let db = try Database(url: url)
        XCTAssertEqual(try db.loadSamples(), [sample]); XCTAssertEqual(try db.loadEvents(), [event])
        try db.prune(before: old.addingTimeInterval(50))
        XCTAssertTrue(try db.loadSamples().isEmpty); XCTAssertEqual(try db.loadEvents(), [event])
        try db.deleteAll(); XCTAssertTrue(try db.loadEvents().isEmpty)
    }
    func testFormatting() {
        XCTAssertEqual(Analytics.duration(-2), "0m"); XCTAssertEqual(Analytics.duration(402 * 60), "6h 42m")
    }
}
