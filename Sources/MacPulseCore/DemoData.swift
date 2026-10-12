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
        return (0..<7).flatMap { day -> [ActivityRecord] in
            var cursor = calendar.date(byAdding: .day, value: -day, to: today)!.addingTimeInterval(9 * 3600)
            return apps.map { bundle, name, minutes, category in
                let seconds = Double(minutes * 60) * (day == 0 ? 1 : [0.72, 0.94, 0.58, 1.08, 0.83, 0.45][day - 1])
                let start = cursor; cursor = cursor.addingTimeInterval(seconds)
                return ActivityRecord(bundleID: bundle, appName: name, start: start, end: cursor, category: category)
            }
        }
    }
    public static func codex(now: Date = Date()) -> [CodexSession] {
        (0..<12).map { index in
            let start = now.addingTimeInterval(-Double(index * 5400 + 1200))
            return CodexSession(id: "demo-\(index)", date: start, lastEvent: start.addingTimeInterval(900 + Double(index * 25)), project: ["MacPulse", "Studio Tools", "Personal Site", "Audio Engine"][index % 4], inputTokens: 12000 + index * 300, outputTokens: 2100 + index * 125)
        }
    }
}
