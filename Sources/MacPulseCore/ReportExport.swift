import Foundation

public enum ReportExportKind: String, CaseIterable, Identifiable {
    case activity = "Activity CSV", daily = "Daily totals CSV", weekly = "Weekly recap CSV"
    case applications = "Applications CSV", sessions = "Sessions CSV", codex = "Codex metadata CSV", json = "Full JSON"
    public var id: String { rawValue }
}
public enum ReportExport {
    public static func csv(kind: ReportExportKind, snapshot: ExportSnapshot, calendar: Calendar = .current, ending: Date? = nil) -> String {
        func quote(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = ["=", "+", "-", "@"].contains(where: trimmed.hasPrefix) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func row(_ values: [String]) -> String { values.map(quote).joined(separator: ",") }
        let formatter = ISO8601DateFormatter()
        func date(_ value: Date) -> String { formatter.string(from: value) }
        let reportEnd = ending ?? snapshot.exportedAt
        var header: [String] = [], rows: [[String]] = []
        switch kind {
        case .activity: return Analytics.csv(snapshot.activity)
        case .daily:
            header = ["local_day", "active_seconds", "session_span_seconds", "source"]
            let start = (snapshot.activity.map(\.start) + snapshot.sessions.map(\.start)).min() ?? snapshot.exportedAt
            let count = min(366, max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: snapshot.exportedAt)).day ?? 0) + 1))
            rows = HistoryAnalytics.daily(records: snapshot.activity, sessions: snapshot.sessions, intervals: snapshot.stateIntervals, ending: reportEnd, count: count, calendar: calendar).map { [date($0.date), $0.seconds.map { String($0) } ?? "", String($0.observedSeconds), $0.seconds == nil ? "Unavailable" : snapshot.source.rawValue] }
        case .weekly:
            header = ["start", "end", "active_seconds", "recorded_days", "previous_week_seconds", "top_application", "codex_sessions", "source"]
            let recap = HistoryAnalytics.recap(records: snapshot.activity, sessions: snapshot.sessions, codex: snapshot.codex, intervals: snapshot.stateIntervals, ending: reportEnd, calendar: calendar)
            rows = [[date(recap.start), date(recap.end), String(recap.total), String(recap.recordedDays), recap.previousTotal.map { String($0) } ?? "", recap.topApp ?? "", String(recap.codexSessions), snapshot.source.rawValue]]
        case .applications:
            header = ["application", "bundle_id", "seconds", "periods", "average_seconds", "longest_seconds", "last_active", "category", "source"]
            rows = HistoryAnalytics.applicationDetails(snapshot.activity, from: .distantPast, to: .distantFuture).map { [ $0.usage.name, $0.usage.bundleID, String($0.usage.seconds), String($0.usage.sessions), String($0.average), String($0.longest), date($0.usage.lastActive), $0.usage.category.rawValue, snapshot.source.rawValue ] }
        case .sessions:
            header = ["id", "start", "end", "active_seconds", "idle_seconds", "sleep_seconds", "switches", "end_reason", "source"]
            rows = snapshot.sessions.map { [$0.id.uuidString, date($0.start), $0.end.map(date) ?? "", String($0.activeSeconds), String($0.idleSeconds), String($0.sleepSeconds), String($0.switches), $0.endReason ?? "Open", snapshot.source.rawValue] }
        case .codex:
            header = ["id", "project", "start", "last_event", "session_span_seconds", "model", "input_tokens", "output_tokens", "cached_tokens", "source"]
            rows = snapshot.codex.map { [$0.id, $0.project, date($0.date), date($0.lastEvent), String($0.duration), $0.model ?? "", $0.inputTokens.map { String($0) } ?? "", $0.outputTokens.map { String($0) } ?? "", $0.cachedTokens.map { String($0) } ?? "", snapshot.source.rawValue] }
        case .json: return ""
        }
        return ([row(header)] + rows.map(row)).joined(separator: "\n") + "\n"
    }
}
