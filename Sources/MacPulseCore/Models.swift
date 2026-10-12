import Foundation

public enum ActivityCategory: String, Codable, CaseIterable, Identifiable {
    case development = "Development", music = "Music Production", gaming = "Gaming"
    case browsing = "Browsing", communication = "Communication", entertainment = "Entertainment", other = "Other"
    public var id: String { rawValue }
    public static func suggested(for bundle: String) -> Self {
        let value = bundle.lowercased()
        if ["xcode", "code", "terminal", "iterm", "codex"].contains(where: value.contains) { return .development }
        if ["steam", "game"].contains(where: value.contains) { return .gaming }
        if ["logic", "ableton", "garageband"].contains(where: value.contains) { return .music }
        if ["safari", "chrome", "firefox"].contains(where: value.contains) { return .browsing }
        if ["slack", "messages", "discord", "mail"].contains(where: value.contains) { return .communication }
        if ["spotify", "music", "tv"].contains(where: value.contains) { return .entertainment }
        return .other
    }
}
public struct ActivityRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var start: Date
    public var end: Date
    public var category: ActivityCategory
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public init(id: UUID = UUID(), bundleID: String, appName: String, start: Date, end: Date, category: ActivityCategory = .other) {
        self.id = id; self.bundleID = bundleID; self.appName = appName; self.start = start; self.end = end; self.category = category
    }
    public func overlap(from: Date, to: Date) -> TimeInterval {
        max(0, min(end, to).timeIntervalSince(max(start, from)))
    }
}
public struct AppUsage: Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let seconds: Double
    public let sessions: Int
    public let lastActive: Date
    public let category: ActivityCategory
}
public struct DailyUsage: Identifiable {
    public var id: Date { date }
    public let date: Date
    public let seconds: Double
}
public enum Analytics {
    public static func applications(_ records: [ActivityRecord], from: Date, to: Date) -> [AppUsage] {
        let relevant = records.filter { $0.overlap(from: from, to: to) > 0 }
        return Dictionary(grouping: relevant, by: \.bundleID).map { key, values in
            let latest = values.max(by: { $0.end < $1.end })!
            return AppUsage(bundleID: key, name: latest.appName, seconds: values.reduce(0) { $0 + $1.overlap(from: from, to: to) }, sessions: values.count, lastActive: latest.end, category: latest.category)
        }.sorted { $0.seconds > $1.seconds }
    }
    public static func days(_ records: [ActivityRecord], ending: Date, count: Int = 7, calendar: Calendar = .current) -> [DailyUsage] {
        let today = calendar.startOfDay(for: ending)
        return (0..<max(0, count)).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today), let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DailyUsage(date: start, seconds: records.reduce(0) { $0 + $1.overlap(from: start, to: end) })
        }
    }
    public static func duration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds) / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
    public static func csv(_ records: [ActivityRecord]) -> String {
        func escape(_ s: String) -> String {
            // Prevent formula execution when a CSV is opened in a spreadsheet.
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = ["=", "+", "-", "@"].contains(where: trimmed.hasPrefix) || ["\t", "\r"].contains(where: s.hasPrefix) ? "'" + s : s
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = ISO8601DateFormatter()
        return "application,bundle_id,start,end,seconds,category\n" + records.map {
            [escape($0.appName), escape($0.bundleID), escape(formatter.string(from: $0.start)), escape(formatter.string(from: $0.end)), String(Int($0.duration)), escape($0.category.rawValue)].joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }
}
public enum NotchState: String { case collapsed, hover, expanded }
public struct NotchInteraction {
    public private(set) var state: NotchState = .collapsed
    public init() {}
    public mutating func enter(hoverEnabled: Bool) { if hoverEnabled && state == .collapsed { state = .hover } }
    public mutating func leave() { if state == .hover { state = .collapsed } }
    public mutating func click() { state = state == .expanded ? .collapsed : .expanded }
    public mutating func dismiss() { state = .collapsed }
}
public struct CodexSession: Codable, Identifiable, Equatable {
    public let id: String
    public let date: Date
    public let lastEvent: Date
    public let project: String
    public let inputTokens: Int?
    public let outputTokens: Int?
    public var duration: Double { max(0, lastEvent.timeIntervalSince(date)) }
    public init(id: String, date: Date, lastEvent: Date, project: String, inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.id = id; self.date = date; self.lastEvent = lastEvent; self.project = project; self.inputTokens = inputTokens; self.outputTokens = outputTokens
    }
}

public struct SystemSample: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let cpu: Double
    public let memoryRatio: Double
    public init(id: UUID = UUID(), date: Date, cpu: Double, memoryRatio: Double) { self.id = id; self.date = date; self.cpu = cpu; self.memoryRatio = memoryRatio }
}
public struct SessionEvent: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let kind: String
    public let application: String?
    public init(id: UUID = UUID(), date: Date, kind: String, application: String? = nil) { self.id = id; self.date = date; self.kind = kind; self.application = application }
}
