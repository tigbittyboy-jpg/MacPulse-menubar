import Foundation

public struct CategoryDay: Identifiable {
    public var id: String { "\(date.timeIntervalSince1970)-\(category.rawValue)" }
    public let date: Date
    public let category: ActivityCategory
    public let seconds: Double
}
public struct ObservedDay: Identifiable, Codable {
    public var id: Date { date }
    public let date: Date
    public let seconds: Double?
    public let observedSeconds: Double
}
public struct ApplicationDetail: Identifiable {
    public var id: String { usage.bundleID }
    public let usage: AppUsage
    public let average: Double
    public let longest: Double
}
public struct WeeklyRecap {
    public let start: Date
    public let end: Date
    public let total: Double
    public let recordedDays: Int
    public let previousTotal: Double?
    public let topApp: String?
    public let mostActiveDay: ObservedDay?
    public let categories: [ActivityCategory: Double]
    public let averageSession: Double?
    public let codexSessions: Int
}
public enum HistoryAnalytics {
    public static func daily(records: [ActivityRecord], sessions: [ComputerSession], ending: Date, count: Int, calendar: Calendar = .current) -> [ObservedDay] {
        let today = calendar.startOfDay(for: ending)
        return (0..<max(0, count)).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today), let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let total = records.reduce(0) { $0 + $1.overlap(from: start, to: end) }
            let observed = sessions.reduce(0.0) { $0 + max(0, min($1.end ?? $1.observedUntil, end).timeIntervalSince(max($1.start, start))) }
            let known = observed > 0 || records.contains { $0.overlap(from: start, to: end) > 0 }
            return ObservedDay(date: start, seconds: known ? total : nil, observedSeconds: observed)
        }
    }
    public static func stacked(records: [ActivityRecord], ending: Date, count: Int, calendar: Calendar = .current) -> [CategoryDay] {
        let today = calendar.startOfDay(for: ending)
        return (0..<max(0, count)).reversed().flatMap { offset -> [CategoryDay] in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today), let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
            return ActivityCategory.allCases.compactMap { category in
                let seconds = records.filter { $0.category == category }.reduce(0) { $0 + $1.overlap(from: start, to: end) }
                return seconds > 0 ? CategoryDay(date: start, category: category, seconds: seconds) : nil
            }
        }
    }
    public static func applicationDetails(_ records: [ActivityRecord], from: Date, to: Date) -> [ApplicationDetail] {
        applicationsWithIntervals(records, from: from, to: to)
    }
    private static func applicationsWithIntervals(_ records: [ActivityRecord], from: Date, to: Date) -> [ApplicationDetail] {
        Analytics.applications(records, from: from, to: to).map { usage in
            let durations = records.filter { $0.bundleID == usage.bundleID }.map { $0.overlap(from: from, to: to) }.filter { $0 > 0 }
            return ApplicationDetail(usage: usage, average: usage.seconds / Double(max(1, durations.count)), longest: durations.max() ?? 0)
        }
    }
    public static func recap(records: [ActivityRecord], sessions: [ComputerSession], codex: [CodexSession], ending: Date, calendar: Calendar = .current) -> WeeklyRecap {
        let days = daily(records: records, sessions: sessions, ending: ending, count: 14, calendar: calendar)
        let recent = Array(days.suffix(7)), previous = Array(days.prefix(7))
        let start = recent.first?.date ?? calendar.startOfDay(for: ending)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: ending))!
        let apps = Analytics.applications(records, from: start, to: end)
        let relevant = sessions.filter { $0.start >= start && $0.start < end && $0.end != nil }
        return WeeklyRecap(start: start, end: end, total: recent.compactMap(\.seconds).reduce(0, +), recordedDays: recent.filter { $0.seconds != nil }.count,
            previousTotal: previous.allSatisfy { $0.seconds != nil } && recent.allSatisfy { $0.seconds != nil } ? previous.compactMap(\.seconds).reduce(0, +) : nil,
            topApp: apps.first?.name, mostActiveDay: recent.filter { $0.seconds != nil }.max { ($0.seconds ?? 0) < ($1.seconds ?? 0) },
            categories: Dictionary(grouping: apps, by: \.category).mapValues { $0.reduce(0) { $0 + $1.seconds } },
            averageSession: relevant.isEmpty ? nil : relevant.reduce(0) { $0 + $1.activeSeconds } / Double(relevant.count),
            codexSessions: codex.filter { $0.date >= start && $0.date < end }.count)
    }
    public static func topProject(_ sessions: [CodexSession]) -> String? {
        Dictionary(grouping: sessions, by: \.project).sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }.first?.key
    }
}
public struct ExportSnapshot: Codable {
    public let schemaVersion: Int
    public let source: DataSourceState
    public let exportedAt: Date
    public let activity: [ActivityRecord]
    public let sessions: [ComputerSession]
    public let stateIntervals: [StateInterval]
    public let codex: [CodexSession]
    public let systemSamples: [SystemSample]
    public let usageReadings: [UsageReading]
    public init(source: DataSourceState, exportedAt: Date = Date(), activity: [ActivityRecord], sessions: [ComputerSession], stateIntervals: [StateInterval], codex: [CodexSession], systemSamples: [SystemSample], usageReadings: [UsageReading] = []) {
        self.schemaVersion = 2; self.usageReadings = usageReadings; self.source = source; self.exportedAt = exportedAt; self.activity = activity; self.sessions = sessions; self.stateIntervals = stateIntervals; self.codex = codex; self.systemSamples = systemSamples
    }
    public func json() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(self) }
}
