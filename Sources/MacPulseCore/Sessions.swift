import Foundation

public enum DataSourceState: String, Codable, CaseIterable {
    case live = "Live", historical = "Historical", estimated = "Estimated", demo = "Demo"
    case unavailable = "Unavailable", permissionRequired = "Permission Required"
}
public enum IntervalKind: String, Codable, CaseIterable { case idle = "Idle", sleep = "Sleep", excluded = "Excluded" }
public struct StateInterval: Codable, Identifiable, Equatable {
    public var id: UUID
    public let sessionID: UUID
    public var start: Date
    public var end: Date
    public let kind: IntervalKind
    public var duration: Double { max(0, end.timeIntervalSince(start)) }
    public init(id: UUID = UUID(), sessionID: UUID, start: Date, end: Date, kind: IntervalKind) { self.id = id; self.sessionID = sessionID; self.start = start; self.end = end; self.kind = kind }
}
public struct ComputerSession: Codable, Identifiable, Equatable {
    public let id: UUID
    public let start: Date
    public var observedUntil: Date
    public var end: Date?
    public var activeSeconds: Double
    public var idleSeconds: Double
    public var sleepSeconds: Double
    public var switches: Int
    public var endReason: String?
    public init(id: UUID = UUID(), start: Date) {
        self.id = id; self.start = start; observedUntil = start; end = nil
        activeSeconds = 0; idleSeconds = 0; sleepSeconds = 0; switches = 0; endReason = nil
    }
    public mutating func close(at: Date, reason: String) { end = max(start, at); observedUntil = max(observedUntil, end!); endReason = reason }
    public mutating func recoverAfterCrash() { if end == nil { end = observedUntil; endReason = "Interrupted · last observation" } }
}
public struct ClockObservation {
    public let activity: ActivityRecord?
    public let idleStart: Date?
    public let idleSeconds: Double
    public let excludedSeconds: Double
    public let switched: Bool
    public let discontinuity: Bool
}
public enum SampleMath {
    /// Aggregate CPU ticks normalize across all cores. Counter reset/wrap yields no reading.
    public static func cpu(previous: [UInt64], current: [UInt64]) -> Double? {
        guard current.count == 4, previous.count == 4, zip(current, previous).allSatisfy({ $0 >= $1 }) else { return nil }
        let delta = zip(current, previous).map { Double($0 - $1) }
        let total = delta.reduce(0, +)
        return total > 0 ? min(1, max(0, 1 - delta[2] / total)) : nil
    }
    public static func rate(previous: UInt64, current: UInt64, seconds: Double) -> Double? {
        guard current >= previous, seconds > 0, seconds.isFinite else { return nil }
        return Double(current - previous) / seconds
    }
    public static func resetCountdown(reset: Date?, now: Date) -> String {
        guard let reset else { return "Unavailable" }
        let value = reset.timeIntervalSince(now)
        guard value.isFinite else { return "Unavailable" }
        if value <= 0 { return "Reset due" }
        let seconds = Int(min(value, Double(Int.max / 2)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}
