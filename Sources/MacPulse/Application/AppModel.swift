#if os(macOS)
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import UserNotifications
import MacPulseCore

@MainActor final class AppModel: ObservableObject {
    let preferences: Preferences
    @Published private(set) var liveRecords: [ActivityRecord] = []
    @Published private(set) var liveCodex: [CodexSession] = []
    @Published private(set) var liveSessions: [ComputerSession] = []
    @Published private(set) var liveIntervals: [StateInterval] = []
    @Published private(set) var savedSamples: [SystemSample] = []
    @Published private(set) var usageHistory: [UsageReading] = []
    @Published var liveSystem = SystemSnapshot()
    @Published private(set) var history: [PerformancePoint] = []
    @Published private(set) var events: [SessionEvent] = []
    @Published private(set) var activeApp = "No foreground application"
    @Published private(set) var activeBundle = ""
    @Published private(set) var diagnostics: [String] = []
    @Published var error: String?
    @Published private(set) var importing = false
    @Published private(set) var refreshingUsage = false
    @Published private(set) var usageStatus = "Not connected"
    @Published private(set) var importStatus = "No folder imported"
    @Published private(set) var now = Date()
    @Published private(set) var sessionStart = Date()
    @Published private(set) var idleSeconds: Double = 0
    @Published private(set) var records: [ActivityRecord] = []
    @Published private(set) var apps: [AppUsage] = []
    var dashboardVisible = false
    var dashboardPage = "Overview"
    private var reportsMode: Bool?
    private var reportCategories: [String: String] = [:]
    var notchExpanded = false
    private var database: Database?
    private var currentSession: ComputerSession?
    private var clock = ActivityClock()
    private let monitor = SystemMonitor()
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var asleep = false
    private var sleepStart: Date?
    private var sampling = false
    private var lastSystemSample: Double = -100
    private var lastSampleSaved = Date.distantPast
    private var lastPrune = Date()
    private var demoRecords = DemoData.activity()
    private var demoSessions = DemoData.sessions()
    private var demoCodex = DemoData.codex()
    private var reportDay = Calendar.current.startOfDay(for: Date())
    private var usageTask: Task<Void, Never>?
    private var lastUsageAttempt = Date.distantPast
    private var alertPolicy = UsageAlertPolicy(delivered: Set(UserDefaults.standard.stringArray(forKey: "deliveredUsageAlerts") ?? []))
    private var pressureSource: DispatchSourceMemoryPressure?
    @Published private(set) var memoryPressure = "Unavailable · awaiting system signal"
    var codex: [CodexSession] { (preferences.demo ? demoCodex : liveCodex).filter { !preferences.isProjectExcluded($0.project) } }
    var sessions: [ComputerSession] { preferences.demo ? demoSessions : liveSessions }
    var intervals: [StateInterval] { preferences.demo ? [] : liveIntervals }
    var system: SystemSnapshot { preferences.demo ? .demo : liveSystem }
    var source: DataSourceState { preferences.demo ? .demo : .historical }
    var today: Date { Calendar.current.startOfDay(for: now) }
    var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today)! }
    var todaySeconds: Double { apps.reduce(0) { $0 + $1.seconds } }
    var sessionSeconds: Double { preferences.demo ? 6420 : currentSession?.activeSeconds ?? 0 }
    var sessionIdle: Double { preferences.demo ? 1080 : currentSession?.idleSeconds ?? 0 }
    var currentAppSeconds: Double { preferences.demo ? 2400 : liveRecords.last.flatMap { $0.bundleID == activeBundle ? $0.duration : nil } ?? 0 }
    var sessionState: String { preferences.demo ? "Demo session" : (asleep ? "Sleeping" : (currentSession == nil ? "Monitoring paused" : (idleSeconds >= preferences.idleThreshold ? "Idle" : "Recording"))) }
    var databaseWarnings: [String] { database?.warnings ?? [] }
    var currentUsage: UsageReading? {
        if preferences.demo {
            return UsageReading(refreshedAt: sessionStart, windows: [UsageWindow(id: "demo.primary", name: "Sample window", usedPercent: 28, durationMinutes: 300, resetsAt: sessionStart.addingTimeInterval(7200))], source: .demo)
        }
        return usageHistory.first
    }
    var usageSource: DataSourceState {
        guard let reading = currentUsage else { return .unavailable }
        return reading.source == .demo ? .demo : (reading.isFresh(at: now) && usageStatus == "Connected" ? .live : .historical)
    }
    var chartHistory: [PerformancePoint] {
        if !preferences.demo { return history }
        return (0..<60).map { i in PerformancePoint(date: now.addingTimeInterval(Double(i - 59) * 5), cpu: 0.18 + sin(Double(i) * 0.4) * 0.06, memory: 0.46 + sin(Double(i) * 0.1) * 0.025, upload: 84_000, download: 2_400_000) }
    }
    init(preferences: Preferences = Preferences(), databaseURL: URL? = nil) {
        self.preferences = preferences
        diagnostics = UserDefaults.standard.stringArray(forKey: "diagnosticLog") ?? []
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("MacPulse")
            database = try Database(url: databaseURL ?? support.appendingPathComponent("activity.sqlite"))
            try database?.prune(before: Date().addingTimeInterval(-Double(preferences.retention) * 86400))
            liveRecords = try database?.load() ?? []; liveCodex = try database?.loadCodex() ?? []
            liveSessions = try database?.recoverInterruptedSessions() ?? []; liveIntervals = try database?.loadIntervals() ?? []
            events = try database?.loadEvents() ?? []; savedSamples = try database?.loadSamples() ?? []
            usageHistory = try database?.loadUsage() ?? []
            history = savedSamples.filter { $0.date > Date().addingTimeInterval(-600) }.reversed().map { PerformancePoint(date: $0.date, cpu: $0.cpu, memory: $0.memoryRatio, upload: $0.upload, download: $0.download) }
        } catch { note(error.localizedDescription) }
        preferences.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.rebuildReports(); self?.objectWillChange.send() }
        }.store(in: &subscriptions)
        preferences.$demo.combineLatest(preferences.$monitoring).dropFirst().sink { [weak self] demo, enabled in
            self?.transitionRecording(enabled && !demo)
        }.store(in: &subscriptions)
        preferences.$retention.dropFirst().sink { [weak self] days in self?.prune(days: days) }.store(in: &subscriptions)
        observeWorkspace()
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            let state = pressure.data
            let message = state.contains(.critical) ? "Critical" : (state.contains(.warning) ? "Warning" : "Normal")
            Task { @MainActor in self?.memoryPressure = message }
        }
        pressure.resume(); pressureSource = pressure
        transitionRecording(preferences.monitoring && !preferences.demo)
        rebuildReports(); tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        timer?.tolerance = 0.25
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, action: @escaping @MainActor (AppModel) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in if let self { action(self) } } })
        }
        observe(NSWorkspace.willSleepNotification) { model in
            model.tick(sampleSystem: false); model.recordEvent("Sleep"); model.asleep = true; model.sleepStart = Date(); model.clock.reset()
        }
        observe(NSWorkspace.didWakeNotification) { model in
            model.asleep = false
            if let start = model.sleepStart, var session = model.currentSession {
                let end = Date()
                if end > start {
                    let interval = StateInterval(sessionID: session.id, start: start, end: end, kind: .sleep)
                    session.sleepSeconds += interval.duration; session.observedUntil = end
                    model.persistFrame(activity: nil, interval: interval, session: session)
                }
            }
            model.sleepStart = nil; model.clock.reset(); model.recordEvent("Wake"); model.tick()
        }
        observe(NSWorkspace.didActivateApplicationNotification) { $0.tick(sampleSystem: false) }
        observe(NSWorkspace.didTerminateApplicationNotification) { $0.tick(sampleSystem: false) }
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName, bundle = app?.bundleIdentifier ?? ""
            Task { @MainActor in guard let self, !self.preferences.isExcluded(bundle) else { return }; self.recordEvent("Application launched", application: name) }
        })
    }
    private func transitionRecording(_ enabled: Bool) {
        if !enabled { closeSession(reason: "Monitoring paused") }
        else if currentSession == nil && database != nil {
            let session = ComputerSession(start: Date()); currentSession = session; sessionStart = session.start
            do { try database?.saveSession(session); liveSessions.insert(session, at: 0) } catch { note(error.localizedDescription) }
        }
        clock.reset()
    }
    private func closeSession(reason: String) {
        guard var session = currentSession else { return }
        session.close(at: session.observedUntil, reason: reason)
        do { try database?.saveSession(session); replaceSession(session) } catch { note(error.localizedDescription) }
        currentSession = nil; clock.reset(); sleepStart = nil
    }
    private func replaceSession(_ session: ComputerSession) {
        if let index = liveSessions.firstIndex(where: { $0.id == session.id }) { liveSessions[index] = session } else { liveSessions.insert(session, at: 0) }
    }
    private func tick(sampleSystem: Bool = true) {
        guard !asleep else { return }
        now = Date()
        if today != reportDay { reportDay = today; demoRecords = DemoData.activity(now: now); demoSessions = DemoData.sessions(now: now); demoCodex = DemoData.codex(now: now); reportsMode = nil }
        // kCGAnyInputEventType: inspect time since any input, not null events.
        idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let app = NSWorkspace.shared.frontmostApplication
        activeBundle = app?.bundleIdentifier ?? "unknown"; activeApp = app?.localizedName ?? "Unknown application"
        let uptime = ProcessInfo.processInfo.systemUptime
        let observation = clock.observe(at: now, uptime: uptime, bundleID: activeBundle, name: activeApp, category: preferences.category(for: activeBundle), enabled: currentSession != nil, idleSeconds: idleSeconds, excluded: preferences.isExcluded(activeBundle), demo: preferences.demo, idleThreshold: preferences.idleThreshold)
        if var session = currentSession {
            session.activeSeconds += observation.activity?.duration ?? 0; session.idleSeconds += observation.idleSeconds
            if observation.switched { session.switches += 1 }
            session.observedUntil = now
            var record = observation.activity
            if let incoming = record, let last = liveRecords.last, last.start >= session.start, last.bundleID == incoming.bundleID, last.category == incoming.category, abs(last.end.timeIntervalSince(incoming.start)) < 0.01, Calendar.current.isDate(last.start, inSameDayAs: incoming.end) {
                record = ActivityRecord(id: last.id, bundleID: last.bundleID, appName: last.appName, start: last.start, end: incoming.end, category: last.category)
            }
            var interval: StateInterval?
            if let start = observation.idleStart, observation.idleSeconds > 0 {
                interval = StateInterval(sessionID: session.id, start: start, end: start.addingTimeInterval(observation.idleSeconds), kind: .idle)
            } else if observation.excludedSeconds > 0 {
                interval = StateInterval(sessionID: session.id, start: now.addingTimeInterval(-observation.excludedSeconds), end: now, kind: .excluded)
            }
            if let incoming = interval, let last = liveIntervals.last, last.sessionID == incoming.sessionID, last.kind == incoming.kind, abs(last.end.timeIntervalSince(incoming.start)) < 0.01 {
                interval = StateInterval(id: last.id, sessionID: last.sessionID, start: last.start, end: incoming.end, kind: incoming.kind)
            }
            persistFrame(activity: record, interval: interval, session: session)
            if observation.discontinuity { recordEvent("Unobserved gap · not counted") }
        }
        rebuildReports()
        let presentationNeeded = dashboardVisible || notchExpanded || preferences.compactIndicator == "CPU"
        let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? max(15, preferences.systemInterval) : (presentationNeeded ? preferences.systemInterval : max(10, preferences.systemInterval))
        if sampleSystem && !sampling && uptime - lastSystemSample >= interval {
            sampling = true; lastSystemSample = uptime
            Task {
                let value = await monitor.sample(includeProcesses: dashboardVisible && dashboardPage == "System")
                liveSystem = value; sampling = false
                if let cpu = value.cpu, value.memoryAvailable {
                    let point = PerformancePoint(date: Date(), cpu: cpu, memory: value.memoryRatio, upload: value.upload, download: value.download)
                    if presentationNeeded { history.append(point); history.removeAll { $0.date < Date().addingTimeInterval(-600) }; if history.count > 300 { history.removeFirst(history.count - 300) } }
                    if currentSession != nil && !preferences.demo && now.timeIntervalSince(lastSampleSaved) >= 60 {
                        let sample = SystemSample(date: now, cpu: cpu, memoryRatio: value.memoryRatio, upload: value.upload, download: value.download)
                        do { try database?.saveSample(sample); savedSamples.insert(sample, at: 0); if savedSamples.count > 5000 { savedSamples.removeLast() }; lastSampleSaved = now } catch { note(error.localizedDescription) }
                    }
                }
            }
        }
        if sampleSystem && now.timeIntervalSince(lastPrune) > 3600 { prune(days: preferences.retention); lastPrune = now }
        if preferences.usageAutoRefresh && !preferences.demo && !preferences.usageExecutable.isEmpty && now.timeIntervalSince(lastUsageAttempt) >= 300 { refreshUsage() }
    }
    private func persistFrame(activity: ActivityRecord?, interval: StateInterval?, session: ComputerSession) {
        do {
            try database?.saveFrame(activity: activity, interval: interval, session: session)
            currentSession = session; replaceSession(session)
            if let activity {
                if liveRecords.last?.id == activity.id { liveRecords[liveRecords.count - 1] = activity } else { liveRecords.append(activity) }
                if !preferences.demo {
                    var displayed = activity
                    if let category = preferences.categories[activity.bundleID].flatMap(ActivityCategory.init(rawValue:)) { displayed.category = category }
                    if records.last?.id == activity.id { records[records.count - 1] = displayed } else { records.append(displayed) }
                }
            }
            if let interval {
                if let index = liveIntervals.lastIndex(where: { $0.id == interval.id }) { liveIntervals[index] = interval } else { liveIntervals.append(interval) }
            }
        } catch { note(error.localizedDescription); currentSession = nil; clock.reset() }
    }
    private func rebuildReports() {
        if reportsMode != preferences.demo || reportCategories != preferences.categories {
        records = (preferences.demo ? demoRecords : liveRecords).map { record in
            var result = record
            if let category = preferences.categories[record.bundleID].flatMap(ActivityCategory.init(rawValue:)) { result.category = category }
            return result
        }
        reportsMode = preferences.demo; reportCategories = preferences.categories
        }
        let recent = preferences.demo ? records : Array(records.reversed().prefix { $0.end >= today })
        apps = Analytics.applications(recent, from: today, to: tomorrow)
    }
    private func prune(days: Int) {
        do {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            try database?.prune(before: cutoff)
            liveRecords.removeAll { $0.end < cutoff }; liveCodex.removeAll { $0.lastEvent < cutoff }
            liveSessions.removeAll { $0.observedUntil < cutoff }; liveIntervals.removeAll { $0.end < cutoff }
            savedSamples.removeAll { $0.date < cutoff }; usageHistory.removeAll { $0.refreshedAt < cutoff }; events.removeAll { $0.date < cutoff }
            reportsMode = nil; rebuildReports()
        } catch { note(error.localizedDescription) }
    }
    func note(_ message: String) {
        error = message
        diagnostics.insert(Date().formatted(date: .abbreviated, time: .shortened) + " · " + message, at: 0)
        diagnostics = Array(diagnostics.prefix(20)); UserDefaults.standard.set(diagnostics, forKey: "diagnosticLog")
    }
    func recordEvent(_ kind: String, application: String? = nil) {
        guard currentSession != nil, !preferences.demo else { return }
        let event = SessionEvent(date: Date(), kind: kind, application: application)
        do { try database?.saveEvent(event); events.insert(event, at: 0); if events.count > 5000 { events.removeLast() } } catch { note(error.localizedDescription) }
    }
    func endSession() {
        tick(sampleSystem: false); closeSession(reason: "MacPulse closed")
        timer?.invalidate(); timer = nil; usageTask?.cancel(); pressureSource?.setEventHandler(handler: nil); pressureSource?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
    }
    func deleteData() {
        do {
            try database?.deleteAll(); liveRecords = []; liveCodex = []; liveSessions = []; liveIntervals = []; usageHistory = []; savedSamples = []; history = []; events = []
            currentSession = nil; reportsMode = nil; clock.reset(); sessionStart = Date(); alertPolicy = UsageAlertPolicy(); UserDefaults.standard.removeObject(forKey: "deliveredUsageAlerts")
            transitionRecording(preferences.monitoring && !preferences.demo); rebuildReports()
        } catch { note(error.localizedDescription) }
    }
    func exportCSV() { export(format: "Activity CSV") }
    func export(format: String, ending: Date? = nil) {
        let panel = NSSavePanel(); let kind = ReportExportKind(rawValue: format) ?? .activity; let json = kind == .json
        panel.allowedContentTypes = json ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = "MacPulse-" + (preferences.demo ? "demo-" : "") + (json ? "history.json" : kind.rawValue.lowercased().replacingOccurrences(of: " csv", with: "").replacingOccurrences(of: " ", with: "-") + ".csv")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
                let samples = preferences.demo ? [] : try database?.loadSamples(limit: 600_000) ?? []
                let snapshot = ExportSnapshot(source: source, activity: records, sessions: sessions, stateIntervals: intervals, codex: codex, systemSamples: samples, usageReadings: preferences.demo ? [] : usageHistory)
            if json { try snapshot.json().write(to: url, options: .atomic) }
            else { try ReportExport.csv(kind: kind, snapshot: snapshot, ending: ending).write(to: url, atomically: true, encoding: .utf8) }
        } catch { note(error.localizedDescription) }
    }
    func importCodex() {
        guard !preferences.demo, !importing else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a Codex sessions folder. Only project names, dates, model names and aggregate token counts are retained."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        importing = true
        Task {
            defer { importing = false }
            do {
                let result = try await CodexImporter.scan(folder: folder)
                guard !preferences.demo else { return }
                let cutoff = Date().addingTimeInterval(-Double(preferences.retention) * 86400)
                var merged = Dictionary(liveCodex.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                for session in result.sessions where session.lastEvent >= cutoff && !preferences.isProjectExcluded(session.project) { merged[session.id] = session }
                let values = merged.values.filter { $0.lastEvent >= cutoff }.sorted { $0.date > $1.date }
                try database?.saveCodex(values); liveCodex = values
                importStatus = "\(result.sessions.count) recognized · \(result.skipped) skipped · refreshed \(Date().formatted(date: .omitted, time: .shortened))"
            } catch { note(error.localizedDescription) }
        }
    }
    func chooseCodexExecutable() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.message = "Select your installed official Codex CLI executable. MacPulse will only initialize app-server and read rate limits."
        if panel.runModal() == .OK, let url = panel.url { preferences.usageExecutable = url.path }
    }
    func refreshUsage() {
        guard !preferences.demo, !refreshingUsage else { return }
        lastUsageAttempt = Date(); refreshingUsage = true; usageStatus = "Refreshing"
        usageTask = Task {
            defer { refreshingUsage = false }
            do {
                let reading = try await AppServerUsageClient.read(executable: URL(fileURLWithPath: preferences.usageExecutable))
                guard !Task.isCancelled, !preferences.demo else { return }
                try database?.saveUsage(reading); usageHistory.insert(reading, at: 0); if usageHistory.count > 3000 { usageHistory.removeLast() }
                usageStatus = "Connected"
                let alerts = alertPolicy.alerts(reading: reading, now: Date(), threshold: preferences.alertThreshold, enabled: preferences.usageAlerts)
                UserDefaults.standard.set(Array(alertPolicy.delivered), forKey: "deliveredUsageAlerts")
                for window in alerts {
                    let content = UNMutableNotificationContent(); content.title = "Codex usage · \(preferences.alertThreshold)% threshold"; content.body = "\(window.name): \(Int(window.usedPercent))% used."
                    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                }
            } catch { usageStatus = "Unavailable · refresh failed"; note(error.localizedDescription) }
        }
    }
}
#endif
