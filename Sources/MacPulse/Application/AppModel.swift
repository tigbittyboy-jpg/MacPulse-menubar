#if os(macOS)
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import MacPulseCore

@MainActor final class AppModel: ObservableObject {
    let preferences = Preferences()
    @Published var liveRecords: [ActivityRecord] = []
    @Published var liveCodex: [CodexSession] = []
    @Published var liveSystem = SystemSnapshot()
    @Published var history: [PerformancePoint] = []
    @Published var events: [SessionEvent] = []
    private var wasIdle = false
    private var lastSampleSaved = Date.distantPast
    @Published var activeApp = "No activity recorded"
    @Published var error: String?
    @Published var importing = false
    @Published var now = Date()
    @Published var sessionStart = Date()
    @Published var idleSeconds: Double = 0
    @Published var launches = 0
    private var database: Database?
    private var clock = ActivityClock()
    private let monitor = SystemMonitor()
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var asleep = false
    private var ticks = 0
    var records: [ActivityRecord] {
        (preferences.demo ? DemoData.activity(now: now) : liveRecords).map { record in
            var result = record
            if let category = preferences.categories[record.bundleID].flatMap(ActivityCategory.init(rawValue:)) { result.category = category }
            return result
        }
    }
    var codex: [CodexSession] { preferences.demo ? DemoData.codex(now: now) : liveCodex }
    var system: SystemSnapshot { preferences.demo ? .demo : liveSystem }
    var today: Date { Calendar.current.startOfDay(for: now) }
    var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today)! }
    var apps: [AppUsage] { Analytics.applications(records, from: today, to: tomorrow) }
    var todaySeconds: Double { apps.reduce(0) { $0 + $1.seconds } }
    var sessionSeconds: Double { preferences.demo ? 6420 : records.reduce(0) { $0 + $1.overlap(from: sessionStart, to: now) } }
    var chartHistory: [PerformancePoint] {
        if !preferences.demo { return history }
        return (0..<60).map { i in PerformancePoint(date: now.addingTimeInterval(Double(i - 59) * 5), cpu: 0.18 + sin(Double(i) * 0.4) * 0.06, memory: 0.46 + sin(Double(i) * 0.1) * 0.025) }
    }
    init() {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("MacPulse")
            database = try Database(url: support.appendingPathComponent("activity.sqlite"))
            try database?.prune(before: Date().addingTimeInterval(-Double(preferences.retention) * 86400))
            liveRecords = try database?.load() ?? []; liveCodex = try database?.loadCodex() ?? []
            events = try database?.loadEvents() ?? []
            history = (try database?.loadSamples() ?? []).filter { $0.date > Date().addingTimeInterval(-600) }.reversed().map { PerformancePoint(date: $0.date, cpu: $0.cpu, memory: $0.memoryRatio) }
        } catch { self.error = error.localizedDescription }
        preferences.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
            self?.clock.reset()
        }.store(in: &subscriptions)
        preferences.$retention.dropFirst().sink { [weak self] days in self?.prune(days: days) }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.recordEvent("Sleep"); self?.asleep = true; self?.clock.reset() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.asleep = false; self?.sessionStart = Date(); self?.clock.reset(); self?.recordEvent("Wake") } })
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let application = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName
            Task { @MainActor in self?.recordEvent("Application launched", application: application) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.tick(sampleSystem: false) } })
        recordEvent("MacPulse launched")
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func tick(sampleSystem: Bool = true) {
        now = Date()
        guard !asleep else { return }
        if sampleSystem {
            liveSystem = monitor.sample()
            if let cpu = liveSystem.cpu, liveSystem.memoryAvailable { history.append(PerformancePoint(date: now, cpu: cpu, memory: liveSystem.memoryRatio)) }
            if history.count > 120 { history.removeFirst(history.count - 120) }
            if !preferences.demo, preferences.monitoring, liveSystem.memoryAvailable, let cpu = liveSystem.cpu, now.timeIntervalSince(lastSampleSaved) >= 60 {
                do { try database?.saveSample(SystemSample(date: now, cpu: cpu, memoryRatio: liveSystem.memoryRatio)); lastSampleSaved = now }
                catch { self.error = error.localizedDescription }
            }
        }
        idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let idle = idleSeconds >= 60
        if idle != wasIdle { recordEvent(idle ? "Idle started" : "Activity resumed"); wasIdle = idle }
        let app = NSWorkspace.shared.frontmostApplication
        let bundle = app?.bundleIdentifier ?? "unknown"
        activeApp = app?.localizedName ?? "Unknown application"
        if let record = clock.tick(at: now, bundleID: bundle, name: activeApp, category: preferences.category(for: bundle), enabled: preferences.monitoring && database != nil, idleSeconds: idleSeconds, excluded: preferences.isExcluded(bundle), demo: preferences.demo) {
            var record = record
            if let last = liveRecords.last, last.bundleID == record.bundleID, last.category == record.category, abs(last.end.timeIntervalSince(record.start)) < 0.01, Calendar.current.isDate(last.start, inSameDayAs: record.end) {
                record = ActivityRecord(id: last.id, bundleID: last.bundleID, appName: last.appName, start: last.start, end: record.end, category: last.category)
                liveRecords[liveRecords.count - 1] = record
            } else { liveRecords.append(record) }
            do { try database?.save(record) } catch { self.error = error.localizedDescription }
        }
        if sampleSystem { ticks += 1; if ticks % 720 == 0 { prune(days: preferences.retention) } }
    }
    private func prune(days: Int) {
        do {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            try database?.prune(before: cutoff)
            liveRecords.removeAll { $0.end < cutoff }; liveCodex.removeAll { $0.lastEvent < cutoff }; events.removeAll { $0.date < cutoff }
        } catch { self.error = error.localizedDescription }
    }
    func recordEvent(_ kind: String, application: String? = nil) {
        guard !preferences.demo, preferences.monitoring, database != nil else { return }
        let event = SessionEvent(date: Date(), kind: kind, application: application)
        do { try database?.saveEvent(event); events.insert(event, at: 0); if events.count > 5000 { events.removeLast() } }
        catch { self.error = error.localizedDescription }
    }
    func endSession() {
        tick(sampleSystem: false); recordEvent("MacPulse closed")
        timer?.invalidate(); timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
    }
    func deleteData() {
        do {
            try database?.deleteAll(); liveRecords = []; liveCodex = []; history = []; events = []; clock.reset(); sessionStart = Date(); launches = 0
        } catch { self.error = error.localizedDescription }
    }
    func exportCSV() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = preferences.demo ? "MacPulse-demo.csv" : "MacPulse-activity.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do { try Analytics.csv(records).write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
        }
    }
    func importCodex() {
        guard !preferences.demo else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Select your Codex sessions folder. Only session metadata and aggregate token counts are stored locally. Messages are never retained."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        importing = true
        Task {
            defer { importing = false }
            do {
                let sessions = try await CodexImporter.scan(folder: folder)
                let cutoff = Date().addingTimeInterval(-Double(preferences.retention) * 86400)
                liveCodex = sessions.filter { $0.lastEvent >= cutoff }
                try database?.saveCodex(liveCodex)
                if sessions.isEmpty { error = "No recognized Codex session metadata found. Local formats may vary by Codex version." }
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
