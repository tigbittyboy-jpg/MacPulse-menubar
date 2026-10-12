import Foundation

/// Accounts only for observed foreground activity; gaps, sleep, and idle time are never reconstructed.
public struct ActivityClock {
    private var last: Date?
    private var app: (String, String, ActivityCategory)?
    public init() {}
    public mutating func reset() { last = nil; app = nil }
    public mutating func tick(at date: Date, bundleID: String, name: String, category: ActivityCategory, enabled: Bool, idleSeconds: Double, excluded: Bool, maxGap: Double = 15, demo: Bool = false) -> ActivityRecord? {
        let recording = enabled && !demo
        defer { last = date; app = recording && !excluded && idleSeconds < 60 ? (bundleID, name, category) : nil }
        guard recording, let start = last, let previous = app, !excluded, idleSeconds < 60 else { return nil }
        let elapsed = date.timeIntervalSince(start)
        guard elapsed > 0, elapsed <= maxGap else { return nil }
        return ActivityRecord(bundleID: previous.0, appName: previous.1, start: start, end: date, category: previous.2)
    }
}
