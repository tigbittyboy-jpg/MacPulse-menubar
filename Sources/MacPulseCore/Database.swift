import Foundation
import CSQLite

public enum DatabaseError: Error, LocalizedError {
    case sqlite(String)
    public var errorDescription: String? { if case .sqlite(let s) = self { return s }; return nil }
}
/// Confined to its caller's actor. Activity is coalesced before storage; all SQL values use bindings.
public final class Database {
    private var db: OpaquePointer?
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { sqlite3_close(db); db = nil; throw DatabaseError.sqlite("Cannot open activity database") }
        do {
            try execute("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=3000; PRAGMA secure_delete=ON;")
            try execute("CREATE TABLE IF NOT EXISTS activity (id TEXT PRIMARY KEY, start REAL NOT NULL, end REAL NOT NULL, payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS activity_date ON activity(end); CREATE TABLE IF NOT EXISTS metadata (id TEXT PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS samples (id TEXT PRIMARY KEY, date REAL NOT NULL, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, date REAL NOT NULL, payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS samples_date ON samples(date); CREATE INDEX IF NOT EXISTS events_date ON events(date);")
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
    public func save(_ record: ActivityRecord) throws {
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
                values.append(try JSONDecoder().decode(ActivityRecord.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))))
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
        return try JSONDecoder().decode([CodexSession].self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
    }
    private func saveJSON<T: Encodable>(_ record: T, id: UUID, date: Date, table: String) throws {
        let stmt = try statement("INSERT OR REPLACE INTO \(table) VALUES (?, ?, ?)"); defer { sqlite3_finalize(stmt) }
        let data = try JSONEncoder().encode(record)
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, transient)
        sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
    private func loadJSON<T: Decodable>(_ type: T.Type, table: String) throws -> [T] {
        let stmt = try statement("SELECT payload FROM \(table) ORDER BY date DESC LIMIT 5000"); defer { sqlite3_finalize(stmt) }
        var result: [T] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let bytes = sqlite3_column_blob(stmt, 0) { result.append(try JSONDecoder().decode(type, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))) }
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw error() }; return result
    }
    public func saveSample(_ sample: SystemSample) throws { try saveJSON(sample, id: sample.id, date: sample.date, table: "samples") }
    public func saveEvent(_ event: SessionEvent) throws { try saveJSON(event, id: event.id, date: event.date, table: "events") }
    public func loadSamples() throws -> [SystemSample] { try loadJSON(SystemSample.self, table: "samples") }
    public func loadEvents() throws -> [SessionEvent] { try loadJSON(SessionEvent.self, table: "events") }
    public func prune(before: Date) throws {
        let stmt = try statement("DELETE FROM activity WHERE end < ?"); defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, before.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        for table in ["samples", "events"] {
            let stmt = try statement("DELETE FROM \(table) WHERE date < ?"); defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, before.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        }
        let codex = try loadCodex().filter { $0.lastEvent >= before }
        try saveCodex(codex)
    }
    public func deleteAll() throws { try execute("DELETE FROM activity; DELETE FROM metadata; DELETE FROM samples; DELETE FROM events; PRAGMA wal_checkpoint(TRUNCATE); VACUUM;") }
}
