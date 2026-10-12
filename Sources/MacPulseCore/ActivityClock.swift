import Foundation

/// Monotonic elapsed time validates wall-clock intervals. Unknown gaps are never backfilled.
public struct ActivityClock {
    private var last: Date?
    private var lastUptime: Double?
    private var app: (String, String, ActivityCategory)?
    private var lastExcluded = false
    private var lastIdle: Double = 0
    public init() {}
    public mutating func reset() { last = nil; lastUptime = nil; app = nil; lastExcluded = false; lastIdle = 0 }
    public mutating func observe(at date: Date, uptime: Double, bundleID: String, name: String, category: ActivityCategory, enabled: Bool, idleSeconds: Double, excluded: Bool, maxGap: Double = 15, demo: Bool = false, idleThreshold: Double = 60) -> ClockObservation {
        let recording = enabled && !demo
        let previousApp = app
        let previousExcluded = lastExcluded
        let previousIdle = lastIdle
        let previousDate = last
        let previousUptime = lastUptime
        defer {
            last = recording ? date : nil; lastUptime = recording ? uptime : nil
            app = recording ? (bundleID, name, category) : nil; lastExcluded = excluded; lastIdle = idleSeconds
        }
        let empty = ClockObservation(activity: nil, idleStart: nil, idleSeconds: 0, excludedSeconds: 0, switched: false, discontinuity: false)
        guard recording, let start = previousDate, let tick = previousUptime, let previousApp else { return empty }
        let elapsed = uptime - tick
        let wall = date.timeIntervalSince(start)
        guard elapsed > 0, elapsed <= maxGap, wall > 0, abs(wall - elapsed) < 2 else {
            return ClockObservation(activity: nil, idleStart: nil, idleSeconds: 0, excludedSeconds: 0, switched: false, discontinuity: true)
        }
        // Only the portion past the configured idle threshold is idle. Clip at the threshold crossing.
        let span = min(elapsed, wall)
        let resumed = previousIdle >= idleThreshold && idleSeconds < idleThreshold
        let idle = resumed ? span - min(span, max(0, idleSeconds)) : (idleSeconds.isFinite ? min(span, max(0, idleSeconds - max(1, idleThreshold))) : span)
        let active = max(0, span - idle)
        let activeStart = resumed ? date.addingTimeInterval(-active) : start
        let activeEnd = resumed ? date : start.addingTimeInterval(active)
        let record = !previousExcluded && active > 0 ? ActivityRecord(bundleID: previousApp.0, appName: previousApp.1, start: activeStart, end: activeEnd, category: previousApp.2) : nil
        return ClockObservation(activity: record, idleStart: idle > 0 ? (resumed ? start : activeEnd) : nil, idleSeconds: idle, excludedSeconds: previousExcluded ? active : 0, switched: previousApp.0 != bundleID && !previousExcluded && !excluded, discontinuity: false)
    }
    /// Compatibility entry point for previous callers. New live callers pass system uptime to observe.
    public mutating func tick(at date: Date, bundleID: String, name: String, category: ActivityCategory, enabled: Bool, idleSeconds: Double, excluded: Bool, maxGap: Double = 15, demo: Bool = false) -> ActivityRecord? {
        observe(at: date, uptime: date.timeIntervalSince1970, bundleID: bundleID, name: name, category: category, enabled: enabled, idleSeconds: idleSeconds, excluded: excluded, maxGap: maxGap, demo: demo).activity
    }
}
