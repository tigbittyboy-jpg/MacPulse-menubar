import Foundation

public struct UsageWindow: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let usedPercent: Double
    public let durationMinutes: Int?
    public let resetsAt: Date?
    public var remainingPercent: Double { max(0, 100 - usedPercent) }
    public init(id: String, name: String, usedPercent: Double, durationMinutes: Int?, resetsAt: Date?) {
        self.id = id; self.name = name; self.usedPercent = usedPercent; self.durationMinutes = durationMinutes; self.resetsAt = resetsAt
    }
}
public struct UsageReading: Codable, Identifiable, Equatable {
    public let id: UUID
    public let refreshedAt: Date
    public let windows: [UsageWindow]
    public let source: DataSourceState
    public init(id: UUID = UUID(), refreshedAt: Date = Date(), windows: [UsageWindow], source: DataSourceState = .live) { self.id = id; self.refreshedAt = refreshedAt; self.windows = windows; self.source = source }
    public func isFresh(at date: Date) -> Bool { source == .live && date.timeIntervalSince(refreshedAt) >= 0 && date.timeIntervalSince(refreshedAt) < 600 }
}
public enum UsageParser {
    /// Official Codex app-server GetAccountRateLimitsResponse. No account identity is retained.
    public static func parse(result: [String: Any], at: Date = Date()) -> UsageReading {
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        let snapshots = buckets?.isEmpty == false ? buckets! : ["codex": result["rateLimits"] as? [String: Any] ?? [:]]
        var windows: [UsageWindow] = []
        for bucket in snapshots.keys.sorted() {
            let snapshot = snapshots[bucket]!
            for slot in ["primary", "secondary"] {
                guard let raw = snapshot[slot] as? [String: Any], let used = raw["usedPercent"] as? Double, used.isFinite, (0...100).contains(used) else { continue }
                let number = (raw["windowDurationMins"] as? NSNumber)?.doubleValue
                let minutes = number.flatMap { $0.isFinite && $0 > 0 && $0 < Double(Int.max) && $0.rounded() == $0 ? Int($0) : nil }
                let reset = (raw["resetsAt"] as? Double).flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                windows.append(UsageWindow(id: bucket + "." + slot, name: (snapshot["limitName"] as? String ?? bucket) + " · " + slot, usedPercent: used, durationMinutes: minutes, resetsAt: reset))
            }
        }
        return UsageReading(refreshedAt: at, windows: windows)
    }
    public static func projectedExhaustion(window: UsageWindow, history: [UsageReading], now: Date) -> Date? {
        guard let reset = window.resetsAt, reset > now else { return nil }
        let candidates = history.filter { $0.source == .live && now.timeIntervalSince($0.refreshedAt) < 3600 && $0.refreshedAt <= now }.sorted { $0.refreshedAt < $1.refreshedAt }
        guard let first = candidates.first(where: { reading in reading.windows.contains { $0.id == window.id && $0.resetsAt == reset } }), let previous = first.windows.first(where: { $0.id == window.id && $0.resetsAt == reset }), now.timeIntervalSince(first.refreshedAt) >= 300, window.usedPercent > previous.usedPercent else { return nil }
        let rate = (window.usedPercent - previous.usedPercent) / now.timeIntervalSince(first.refreshedAt)
        return now.addingTimeInterval(window.remainingPercent / rate)
    }
}
public struct UsageAlertPolicy {
    public private(set) var delivered: Set<String>
    public init(delivered: Set<String> = []) { self.delivered = delivered }
    public mutating func alerts(reading: UsageReading, now: Date, threshold: Int, enabled: Bool) -> [UsageWindow] {
        guard enabled, reading.isFresh(at: now), [50, 80, 95].contains(threshold) else { return [] }
        let prefixes = reading.windows.compactMap { window in window.resetsAt.map { "\(window.id)-\($0.timeIntervalSince1970)-" } }
        delivered = Set(delivered.filter { key in prefixes.contains { key.hasPrefix($0) } })
        return reading.windows.filter { window in
            guard let reset = window.resetsAt, reset > now, window.usedPercent >= Double(threshold) else { return false }
            let key = "\(window.id)-\(reset.timeIntervalSince1970)-\(threshold)"
            return delivered.insert(key).inserted
        }
    }
}
