import XCTest
import CSQLite
@testable import MacPulseCore

final class UpgradeTests: XCTestCase {
    private func folder() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
    func testIdleThresholdClipsCrossingAndResumption() {
        var clock = ActivityClock(); let t = Date(timeIntervalSince1970: 1000)
        func observe(_ offset: Double, _ idle: Double) -> ClockObservation {
            clock.observe(at: t.addingTimeInterval(offset), uptime: 100 + offset, bundleID: "a", name: "A", category: .development, enabled: true, idleSeconds: idle, excluded: false)
        }
        _ = observe(0, 58)
        let crossing = observe(5, 63)
        XCTAssertEqual(crossing.activity?.duration, 2); XCTAssertEqual(crossing.idleSeconds, 3)
        let idle = observe(10, 68)
        XCTAssertNil(idle.activity); XCTAssertEqual(idle.idleSeconds, 5)
        let resume = observe(15, 2)
        XCTAssertEqual(resume.activity?.start, t.addingTimeInterval(13)); XCTAssertEqual(resume.activity?.duration, 2)
        XCTAssertEqual(resume.idleSeconds, 3); XCTAssertEqual(resume.idleStart, t.addingTimeInterval(10))
    }
    func testClockChangesAndMissedSamplesAreNotCounted() {
        var clock = ActivityClock(); let t = Date()
        func observe(date: Date, uptime: Double) -> ClockObservation {
            clock.observe(at: date, uptime: uptime, bundleID: "a", name: "A", category: .other, enabled: true, idleSeconds: 0, excluded: false)
        }
        _ = observe(date: t, uptime: 100)
        let jumped = observe(date: t.addingTimeInterval(3600), uptime: 105)
        XCTAssertTrue(jumped.discontinuity); XCTAssertNil(jumped.activity)
        let resumed = observe(date: t.addingTimeInterval(3605), uptime: 110)
        XCTAssertEqual(resumed.activity?.duration, 5)
        XCTAssertTrue(observe(date: t.addingTimeInterval(3700), uptime: 205).discontinuity)
    }
    func testExcludedAppDoesNotErasePreviousAppInterval() {
        var clock = ActivityClock(); let t = Date()
        _ = clock.observe(at: t, uptime: 100, bundleID: "a", name: "A", category: .other, enabled: true, idleSeconds: 0, excluded: false)
        let first = clock.observe(at: t.addingTimeInterval(4), uptime: 104, bundleID: "private", name: "Private", category: .other, enabled: true, idleSeconds: 0, excluded: true)
        XCTAssertEqual(first.activity?.bundleID, "a"); XCTAssertEqual(first.activity?.duration, 4)
        let second = clock.observe(at: t.addingTimeInterval(8), uptime: 108, bundleID: "b", name: "B", category: .other, enabled: true, idleSeconds: 0, excluded: false)
        XCTAssertNil(second.activity); XCTAssertEqual(second.excludedSeconds, 4)
    }
    func testCPUAndNetworkCounterResets() {
        XCTAssertEqual(SampleMath.cpu(previous: [100, 100, 100, 100], current: [120, 110, 170, 100]) ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertNil(SampleMath.cpu(previous: [100, 100, 100, 100], current: [1, 2, 3, 4]))
        XCTAssertNil(SampleMath.cpu(previous: [1, 2, 3, 4], current: [1, 2, 3, 4]))
        XCTAssertEqual(SampleMath.rate(previous: 100, current: 200, seconds: 2), 50)
        XCTAssertNil(SampleMath.rate(previous: 200, current: 100, seconds: 2))
        XCTAssertNil(SampleMath.rate(previous: 100, current: 200, seconds: 0))
    }
    func testMissingDaysStayUnknownAndObservedIdleDayIsZero() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let t = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var session = ComputerSession(start: t.addingTimeInterval(3600)); session.observedUntil = t.addingTimeInterval(7200); session.idleSeconds = 3600
        let days = HistoryAnalytics.daily(records: [], sessions: [session], ending: t, count: 2, calendar: calendar)
        XCTAssertNil(days.first?.seconds); XCTAssertEqual(days.last?.seconds, 0); XCTAssertEqual(days.last?.observedSeconds, 3600)
        let recap = HistoryAnalytics.recap(records: [], sessions: [session], codex: [], ending: t, calendar: calendar)
        XCTAssertEqual(recap.recordedDays, 1); XCTAssertNil(recap.previousTotal)
    }
    func testDSTUsesCalendarDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(end.timeIntervalSince(start), 23 * 3600)
        let record = ActivityRecord(bundleID: "a", appName: "A", start: start, end: end)
        XCTAssertEqual(HistoryAnalytics.daily(records: [record], sessions: [], ending: start, count: 1, calendar: calendar).first?.seconds, 23 * 3600)
    }
    func testSessionCrashRecoveryDoesNotBackfill() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.sqlite"); let t = Date(timeIntervalSince1970: 1000)
        var session = ComputerSession(start: t); session.observedUntil = t.addingTimeInterval(12); session.activeSeconds = 12
        do { let db = try Database(url: url); try db.saveSession(session) }
        let db = try Database(url: url); let recovered = try XCTUnwrap(db.recoverInterruptedSessions().first)
        XCTAssertEqual(recovered.end, t.addingTimeInterval(12)); XCTAssertEqual(recovered.activeSeconds, 12)
        XCTAssertEqual(recovered.endReason, "Interrupted · last observation")
    }
    func testAtomicFrameRollsBackIfIntervalInvalid() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let db = try Database(url: root.appendingPathComponent("db.sqlite")); let t = Date()
        let session = ComputerSession(start: t)
        let record = ActivityRecord(bundleID: "a", appName: "A", start: t, end: t.addingTimeInterval(5))
        let invalid = StateInterval(sessionID: session.id, start: t, end: t, kind: .idle)
        XCTAssertThrowsError(try db.saveFrame(activity: record, interval: invalid, session: session))
        XCTAssertTrue(try db.load().isEmpty); XCTAssertTrue(try db.loadSessions().isEmpty)
        try db.saveFrame(activity: record, interval: nil, session: session)
        XCTAssertEqual(try db.load().count, 1); XCTAssertEqual(try db.loadSessions().count, 1)
    }
    func testLegacyDatabaseMigrationAndCorruptionIsolation() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("legacy.sqlite")
        var handle: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE activity(id TEXT PRIMARY KEY, start REAL NOT NULL, end REAL NOT NULL, payload BLOB NOT NULL); INSERT INTO activity VALUES ('broken',0,10,'broken json');", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let db = try Database(url: url)
        let t = Date(); let good = ActivityRecord(bundleID: "a", appName: "A", start: t, end: t.addingTimeInterval(5))
        try db.save(good)
        XCTAssertEqual(try db.load(), [good]); XCTAssertFalse(db.warnings.isEmpty)
        XCTAssertEqual(try db.loadSessions().count, 0)
    }
    func testFutureSchemaRefusedWithoutReset() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("future.sqlite"); var handle: OpaquePointer?
        sqlite3_open(url.path, &handle); sqlite3_exec(handle, "PRAGMA user_version=99; CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES ('preserved');", nil, nil, nil); sqlite3_close(handle)
        XCTAssertThrowsError(try Database(url: url))
        sqlite3_open(url.path, &handle); defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?; sqlite3_prepare_v2(handle, "SELECT value FROM sentinel", -1, &stmt, nil); defer { sqlite3_finalize(stmt) }
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW); XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 0)), "preserved")
    }
    func testOldOptionalMetadataStillDecodes() throws {
        let codex = #"{"id":"old","date":0,"lastEvent":100,"project":"A"}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(CodexSession.self, from: codex)
        XCTAssertNil(value.model); XCTAssertNil(value.cachedTokens)
        let sample = #"{"id":"00000000-0000-0000-0000-000000000001","date":0,"cpu":0.2,"memoryRatio":0.4}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(SystemSample.self, from: sample).download)
    }
    func testCodexModelAndCachedTokensAndNegativeCounts() throws {
        let lines = [#"{"type":"session_meta","payload":{"id":"s","timestamp":"2026-01-01T12:00:00Z","cwd":"/private/project"}}"#,
                     #"{"type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
                     #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":-1,"cached_input_tokens":70}}}}"#]
        let value = try XCTUnwrap(CodexParser.parse(lines: lines))
        XCTAssertEqual(value.model, "gpt-5-codex"); XCTAssertEqual(value.cachedTokens, 70); XCTAssertNil(value.outputTokens)
    }
    func testUsageMultiBucketParseAndUnknownValues() throws {
        let result: [String: Any] = ["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 82.0, "windowDurationMins": 300, "resetsAt": 2_000_000_000.0]], "other": ["secondary": ["usedPercent": -5.0]]]]
        let reading = UsageParser.parse(result: result)
        XCTAssertEqual(reading.windows.count, 1); XCTAssertEqual(reading.windows.first?.remainingPercent, 18)
        XCTAssertEqual(reading.windows.first?.durationMinutes, 300)
        XCTAssertTrue(UsageParser.parse(result: [:]).windows.isEmpty)
    }
    func testUsageAlertsAreFreshLiveDeduplicatedAndResetAware() {
        let t = Date(timeIntervalSince1970: 1000)
        let window = UsageWindow(id: "codex.primary", name: "Codex", usedPercent: 85, durationMinutes: nil, resetsAt: t.addingTimeInterval(1000))
        var policy = UsageAlertPolicy()
        XCTAssertTrue(policy.alerts(reading: UsageReading(refreshedAt: t, windows: [window], source: .demo), now: t, threshold: 80, enabled: true).isEmpty)
        XCTAssertTrue(policy.alerts(reading: UsageReading(refreshedAt: t, windows: [window]), now: t.addingTimeInterval(700), threshold: 80, enabled: true).isEmpty)
        XCTAssertEqual(policy.alerts(reading: UsageReading(refreshedAt: t, windows: [window]), now: t, threshold: 80, enabled: true).count, 1)
        XCTAssertTrue(policy.alerts(reading: UsageReading(refreshedAt: t, windows: [window]), now: t, threshold: 80, enabled: true).isEmpty)
    }
    func testResetAndProjectionRequireEvidence() {
        let t = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(SampleMath.resetCountdown(reset: nil, now: t), "Unavailable")
        XCTAssertEqual(SampleMath.resetCountdown(reset: t.addingTimeInterval(3661), now: t), "01:01:01")
        XCTAssertEqual(SampleMath.resetCountdown(reset: t, now: t), "Reset due")
        let reset = t.addingTimeInterval(4000)
        let window = UsageWindow(id: "a", name: "A", usedPercent: 40, durationMinutes: nil, resetsAt: reset)
        XCTAssertNil(UsageParser.projectedExhaustion(window: window, history: [], now: t))
        let old = UsageWindow(id: "a", name: "A", usedPercent: 20, durationMinutes: nil, resetsAt: reset)
        let projection = UsageParser.projectedExhaustion(window: window, history: [UsageReading(refreshedAt: t.addingTimeInterval(-600), windows: [old])], now: t)
        XCTAssertEqual(projection, t.addingTimeInterval(1800))
    }
    func testOfficialAppServerHandshakeAgainstDeterministicChild() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-codex")
        let script = #"""
        #!/usr/bin/env python3
        import sys,json
        assert sys.argv[1:]==['app-server']
        first=json.loads(sys.stdin.readline()); assert first['method']=='initialize'
        print(json.dumps({'id':1,'result':{}}),flush=True)
        assert json.loads(sys.stdin.readline())=={'method':'initialized'}
        request=json.loads(sys.stdin.readline()); assert request['method']=='account/rateLimits/read'
        print(json.dumps({'id':2,'result':{'rateLimits':{'primary':{'usedPercent':42,'windowDurationMins':120,'resetsAt':2000000000}}}}),flush=True)
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let reading = try await AppServerUsageClient.read(executable: executable, timeout: 3)
        XCTAssertEqual(reading.windows.first?.usedPercent, 42)
    }
    func testAppServerTimeoutAndMissingExecutable() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        do { _ = try await AppServerUsageClient.read(executable: root.appendingPathComponent("missing")); XCTFail("Missing executable accepted") } catch { XCTAssertTrue(error is UsageClientError) }
        let executable = root.appendingPathComponent("slow")
        try "#!/usr/bin/env python3\nimport time\ntime.sleep(2)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        do { _ = try await AppServerUsageClient.read(executable: executable, timeout: 0.1); XCTFail("No timeout") } catch { XCTAssertEqual(error as? UsageClientError, .timeout) }
    }
    func testPreferenceDefaultsPreserveExistingUserChoices() throws {
        let name = "MacPulse.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "demo"); defaults.set(true, forKey: "monitoring"); defaults.set("Light", forKey: "appearance")
        SettingsSchema.register(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: "demo")); XCTAssertTrue(defaults.bool(forKey: "monitoring"))
        XCTAssertEqual(defaults.string(forKey: "appearance"), "Light"); XCTAssertTrue(defaults.bool(forKey: "notchEnabled"))
        XCTAssertEqual(SettingsSchema.clamped(.nan, range: 0.05...0.7, fallback: 0.15), 0.15)
        XCTAssertEqual(SettingsSchema.clamped(-3, range: 0.05...0.7, fallback: 0.15), 0.05)
    }
    func testAllExportsIncludeRealSourceAndUnknownsStayBlank() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let record = ActivityRecord(bundleID: "test", appName: "=formula", start: now.addingTimeInterval(-10), end: now)
        let codex = CodexSession(id: "test", date: now, lastEvent: now, project: "A")
        let snapshot = ExportSnapshot(source: .historical, exportedAt: now, activity: [record], sessions: [], stateIntervals: [], codex: [codex], systemSamples: [])
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.json()) as? [String: Any])
        XCTAssertEqual(decoded["source"] as? String, "Historical"); XCTAssertEqual(decoded["schemaVersion"] as? Int, 2)
        XCTAssertTrue(ReportExport.csv(kind: .applications, snapshot: snapshot).contains("'=formula"))
        XCTAssertTrue(ReportExport.csv(kind: .codex, snapshot: snapshot).contains("cached_tokens"))
        XCTAssertFalse(ReportExport.csv(kind: .codex, snapshot: snapshot).contains("\"0\""))
        for kind in ReportExportKind.allCases where kind != .json { XCTAssertTrue(ReportExport.csv(kind: kind, snapshot: snapshot).hasSuffix("\n")) }
    }

}
