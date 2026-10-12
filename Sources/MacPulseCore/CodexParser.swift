import Foundation

/// Reads metadata and aggregate token counts only. Never retains messages or auth files.
/// Local JSONL is version-dependent, so unknown events are deliberately ignored.
public enum CodexParser {
    public static func parse(lines: [String]) -> CodexSession? {
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: Any?) -> Date? {
            guard let s = value as? String else { return nil }
            return fractional.date(from: s) ?? formatter.date(from: s)
        }
        var id: String?, start: Date?, end: Date?, project = "Unknown project", input: Int?, output: Int?, cached: Int?, model: String?
        for line in lines {
            guard let data = line.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let type = obj["type"] as? String, let payload = obj["payload"] as? [String: Any] else { continue }
            if let time = date(obj["timestamp"]) { end = max(end ?? time, time) }
            if type == "session_meta" {
                id = payload["id"] as? String
                start = date(payload["timestamp"]) ?? date(obj["timestamp"])
                if let cwd = payload["cwd"] as? String { project = URL(fileURLWithPath: cwd).lastPathComponent }
            }
            if type == "turn_context" { model = payload["model"] as? String ?? model }
            if type == "event_msg", payload["type"] as? String == "token_count", let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any] {
                input = (usage["input_tokens"] as? Int).flatMap { $0 >= 0 ? $0 : nil }; output = (usage["output_tokens"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
                cached = (usage["cached_input_tokens"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
            }
        }
        guard let id, !id.isEmpty, let start, start.timeIntervalSince1970.isFinite else { return nil }
        return CodexSession(id: id, date: start, lastEvent: max(start, end ?? start), project: project, inputTokens: input, outputTokens: output, cachedTokens: cached, model: model)
    }
}
