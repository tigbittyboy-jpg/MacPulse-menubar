import Foundation

public enum DemoData {
    public static func activity(now: Date = Date(), calendar: Calendar = .current) -> [ActivityRecord] {
        let today = calendar.startOfDay(for: now)
        let apps: [(String, String, Int, ActivityCategory)] = [
            ("com.apple.dt.Xcode", "Xcode", 195, .development),
            ("com.apple.logic10", "Logic Pro", 100, .music),
            ("com.valvesoftware.steam", "Steam", 52, .gaming),
            ("com.apple.Safari", "Safari", 55, .browsing)
        ]
        return (0..<14).flatMap { day -> [ActivityRecord] in
            var cursor = calendar.date(byAdding: .day, value: -day, to: today)!.addingTimeInterval(9 * 3600)
            return apps.map { bundle, name, minutes, category in
                let seconds = Double(minutes * 60) * (day == 0 ? 1 : [0.72, 0.94, 0.58, 1.08, 0.83, 0.45][(day - 1) % 6])
                let start = cursor; cursor = cursor.addingTimeInterval(seconds)
                return ActivityRecord(bundleID: bundle, appName: name, start: start, end: cursor, category: category)
            }
        }
    }
    public static func sessions(now: Date = Date()) -> [ComputerSession] {
        let grouped = Dictionary(grouping: activity(now: now), by: { Calendar.current.startOfDay(for: $0.start) })
        return grouped.keys.sorted(by: >).map { day in
            let records = grouped[day]!.sorted { $0.start < $1.start }
            var session = ComputerSession(start: records.first!.start)
            session.activeSeconds = records.reduce(0) { $0 + $1.duration }; session.idleSeconds = 1800; session.switches = 8
            session.close(at: records.last!.end.addingTimeInterval(1800), reason: "Sample session")
            return session
        }
    }
    public static func codex(now: Date = Date()) -> [CodexSession] {
        (0..<12).map { index in
            let start = now.addingTimeInterval(-Double(index * 5400 + 1200))
            return CodexSession(id: "demo-\(index)", date: start, lastEvent: start.addingTimeInterval(900 + Double(index * 25)), project: ["MacPulse", "Studio Tools", "Personal Site", "Audio Engine"][index % 4], inputTokens: 12000 + index * 300, outputTokens: 2100 + index * 125, cachedTokens: 7200 + index * 100, model: index % 3 == 0 ? "gpt-5-codex" : "gpt-5.1-codex")
        }
    }
}
