import Foundation
import CSQLite

public enum DatabaseError: Error, LocalizedError {
    case sqlite(String)
    public var errorDescription: String? { if case .sqlite(let s) = self { return s }; return nil }
}
/// Confined to its caller's actor. Activity is coalesced before storage; all SQL values use bindings.
public final class Database {
    private var db: OpaquePointer?
    public private(set) var warnings: [String] = []
    public let schemaVersion = 2
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { sqlite3_close(db); db = nil; throw DatabaseError.sqlite("Cannot open activity database") }
        do {
            try execute("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=3000; PRAGMA secure_delete=ON;")
            let versionStatement = try statement("PRAGMA user_version")
            sqlite3_step(versionStatement)
            let version = sqlite3_column_int(versionStatement, 0)
            sqlite3_finalize(versionStatement)
            guard version <= schemaVersion else { throw DatabaseError.sqlite("This database was created by a newer MacPulse version. No data was changed.") }
            try transaction {
                try execute("CREATE TABLE IF NOT EXISTS activity (id TEXT PRIMARY KEY, start REAL NOT NULL, end REAL NOT NULL, payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS activity_date ON activity(end); CREATE TABLE IF NOT EXISTS metadata (id TEXT PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS samples (id TEXT PRIMARY KEY, date REAL NOT NULL, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, date REAL NOT NULL, payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS samples_date ON samples(date); CREATE INDEX IF NOT EXISTS events_date ON events(date); CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, date REAL NOT NULL, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS state_intervals (id TEXT PRIMARY KEY, date REAL NOT NULL, payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS sessions_date ON sessions(date); CREATE INDEX IF NOT EXISTS intervals_date ON state_intervals(date); CREATE TABLE IF NOT EXISTS usage_samples (id TEXT PRIMARY KEY, date REAL NOT NULL, payload BLOB NOT NULL); PRAGMA user_version=2;")
            }
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    private func error() -> DatabaseError { .sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Database closed") }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK, let result else { throw error() }
        return result
    }
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try operation(); try execute("COMMIT") } catch { try? execute("ROLLBACK"); throw error }
    }
    private func warn(_ text: String) { if warnings.count < 20 && !warnings.contains(text) { warnings.append(text) } }
    public func save(_ record: ActivityRecord) throws {
        guard record.start.timeIntervalSince1970.isFinite, record.end.timeIntervalSince1970.isFinite, record.end > record.start else { throw DatabaseError.sqlite("Invalid activity interval was not saved") }
        let data = try JSONEncoder().encode(record)
        let stmt = try statement("INSERT OR REPLACE INTO activity VALUES (?, ?, ?, ?)"); defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, transient)
        sqlite3_bind_double(stmt, 2, record.start.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 3, record.end.timeIntervalSince1970)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
    public func load() throws -> [ActivityRecord] {
        let stmt = try statement("SELECT payload FROM activity ORDER BY start"); defer { sqlite3_finalize(stmt) }
        var values: [ActivityRecord] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let bytes = sqlite3_column_blob(stmt, 0) {
                do {
                    let record = try JSONDecoder().decode(ActivityRecord.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
                    if record.end > record.start { values.append(record) } else { warn("An invalid activity interval is preserved in storage but omitted from reports.") }
                } catch { warn("An unreadable activity record is preserved in storage but omitted from reports.") }
            }
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw error() }
        return values
    }
    public func saveCodex(_ records: [CodexSession]) throws {
        let stmt = try statement("INSERT OR REPLACE INTO metadata VALUES ('codex', ?)"); defer { sqlite3_finalize(stmt) }
        let data = try JSONEncoder().encode(records)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
    public func loadCodex() throws -> [CodexSession] {
        let stmt = try statement("SELECT payload FROM metadata WHERE id='codex'"); defer { sqlite3_finalize(stmt) }
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE { return [] }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { throw error() }
        do { return try JSONDecoder().decode([CodexSession].self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))) }
        catch { warn("Stored Codex metadata could not be decoded. Other history remains available."); return [] }
    }
    private func saveJSON<T: Encodable>(_ record: T, id: UUID, date: Date, table: String) throws {
        let stmt = try statement("INSERT OR REPLACE INTO \(table) VALUES (?, ?, ?)"); defer { sqlite3_finalize(stmt) }
        let data = try JSONEncoder().encode(record)
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, transient)
        sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
    private func loadJSON<T: Decodable>(_ type: T.Type, table: String, limit: Int = 100_000) throws -> [T] {
        let stmt = try statement("SELECT payload FROM \(table) ORDER BY date DESC LIMIT \(max(1, min(limit, 600_000)))"); defer { sqlite3_finalize(stmt) }
        var result: [T] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let bytes = sqlite3_column_blob(stmt, 0) {
                do { result.append(try JSONDecoder().decode(type, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))) }
                catch { warn("An unreadable \(table) record is preserved but omitted from reports.") }
            }
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw error() }; return result
    }
    public func saveSample(_ sample: SystemSample) throws { try saveJSON(sample, id: sample.id, date: sample.date, table: "samples") }
    public func saveEvent(_ event: SessionEvent) throws { try saveJSON(event, id: event.id, date: event.date, table: "events") }
    public func loadSamples(limit: Int = 5000) throws -> [SystemSample] { try loadJSON(SystemSample.self, table: "samples", limit: limit) }
    public func loadEvents() throws -> [SessionEvent] { try loadJSON(SessionEvent.self, table: "events") }
    public func saveUsage(_ reading: UsageReading) throws { try saveJSON(reading, id: reading.id, date: reading.refreshedAt, table: "usage_samples") }
    public func loadUsage() throws -> [UsageReading] { try loadJSON(UsageReading.self, table: "usage_samples", limit: 3000) }
    public func loadSessions() throws -> [ComputerSession] { try loadJSON(ComputerSession.self, table: "sessions") }
    public func loadIntervals() throws -> [StateInterval] { try loadJSON(StateInterval.self, table: "state_intervals") }
    public func saveSession(_ session: ComputerSession) throws { try saveJSON(session, id: session.id, date: session.observedUntil, table: "sessions") }
    public func saveInterval(_ interval: StateInterval) throws {
        guard interval.end > interval.start else { throw DatabaseError.sqlite("Invalid state interval") }
        try saveJSON(interval, id: interval.id, date: interval.end, table: "state_intervals")
    }
    public func saveFrame(activity: ActivityRecord?, interval: StateInterval?, session: ComputerSession) throws {
        try transaction { if let activity { try save(activity) }; if let interval { try saveInterval(interval) }; try saveSession(session) }
    }
    public func recoverInterruptedSessions() throws -> [ComputerSession] {
        var sessions = try loadSessions()
        try transaction {
            for index in sessions.indices where sessions[index].end == nil { sessions[index].recoverAfterCrash(); try saveSession(sessions[index]) }
        }
        return sessions
    }
    public func prune(before: Date) throws { try transaction { try pruneRows(before: before) } }
    private func pruneRows(before: Date) throws {
        let stmt = try statement("DELETE FROM activity WHERE end < ?"); defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, before.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        for table in ["samples", "events", "sessions", "state_intervals", "usage_samples"] {
            let stmt = try statement("DELETE FROM \(table) WHERE date < ?"); defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, before.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        }
        let codex = try loadCodex().filter { $0.lastEvent >= before }
        try saveCodex(codex)
    }
    public func deleteAll() throws {
        try transaction { try execute("DELETE FROM activity; DELETE FROM metadata; DELETE FROM samples; DELETE FROM events; DELETE FROM sessions; DELETE FROM state_intervals; DELETE FROM usage_samples;") }
        try execute("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
    }
}
