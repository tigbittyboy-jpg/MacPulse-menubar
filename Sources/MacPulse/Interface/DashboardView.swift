#if os(macOS)
import SwiftUI
import Charts
import MacPulseCore

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview = "Overview", screenTime = "Screen Time", codex = "Codex", applications = "Applications", system = "System", sessions = "Sessions", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .screenTime: return "hourglass"
        case .codex: return "terminal"
        case .applications: return "app.badge"
        case .system: return "cpu"
        case .sessions: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "A little clarity for your day."
        case .screenTime: return "Where your time goes, at a glance."
        case .codex: return "Your coding sessions, kept local."
        case .applications: return "The tools that shape your day."
        case .system: return "A quiet pulse on your Mac."
        case .sessions: return "Your activity, one moment at a time."
        case .settings: return "Make MacPulse feel like yours."
        }
    }
}
struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var page: DashboardPage = .overview
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 22)).foregroundStyle(PulseStyle.blue)
                    Text("MacPulse").font(.system(size: 19, weight: .semibold, design: .rounded))
                }.padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 30)
                ForEach(DashboardPage.allCases) { item in
                    Button { page = item } label: {
                        HStack(spacing: 12) { Image(systemName: item.symbol).frame(width: 18); Text(item.rawValue); Spacer() }
                            .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                            .foregroundStyle(page == item ? Color.primary : Color.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(page == item ? PulseStyle.blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 9) {
                    Label(preferences.demo ? "Demonstration mode" : "On this Mac", systemImage: preferences.demo ? "sparkles" : "lock.shield")
                        .font(.caption).foregroundStyle(preferences.demo ? PulseStyle.violet : PulseStyle.cyan)
                    Text(preferences.demo ? "Sample data. No live history is recorded." : "Private by design. No data leaves this Mac.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(18)
            }.navigationSplitViewColumnWidth(220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if preferences.demo {
                        HStack(spacing: 9) {
                            Image(systemName: "sparkles").foregroundStyle(PulseStyle.violet)
                            Text("You're exploring demo data.").fontWeight(.medium)
                            Text("All statistics below are simulated.").foregroundStyle(.secondary)
                            Spacer()
                            Button("Go live") { preferences.demo = false }.buttonStyle(.bordered)
                        }.font(.caption).padding(14).background(PulseStyle.violet.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    }
                    switch page {
                    case .overview: OverviewPage(model: model)
                    case .screenTime: ScreenTimePage(model: model)
                    case .codex: CodexPage(model: model)
                    case .applications: ApplicationsPage(model: model, preferences: preferences)
                    case .system: SystemPage(model: model)
                    case .sessions: SessionsPage(model: model)
                    case .settings: SettingsView(model: model, preferences: preferences).frame(minHeight: 980)
                    }
                }.padding(30).frame(maxWidth: 1200)
            }.background(preferences.appearance == "Light" ? Color(nsColor: .windowBackgroundColor) : PulseStyle.background)
        }.preferredColorScheme(preferences.appearance == "System" ? nil : (preferences.appearance == "Light" ? .light : .dark))
            .alert("MacPulse", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(page.rawValue).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(page.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Text(model.now, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 5) { Circle().fill(preferences.demo ? PulseStyle.violet : PulseStyle.cyan).frame(width: 5, height: 5); Text(preferences.demo ? "Demo" : "Live system metrics").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.top, 6)
        }
    }
}
struct OverviewPage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MetricCard(title: "Active today", value: Analytics.duration(model.todaySeconds), detail: model.preferences.demo ? "A productive day, in balance" : "Recorded since monitoring began", symbol: "hourglass", tint: PulseStyle.blue)
                MetricCard(title: "Current session", value: Analytics.duration(model.sessionSeconds), detail: "Active time since launch or wake", symbol: "clock", tint: PulseStyle.cyan)
                MetricCard(title: "Codex sessions", value: "\(model.codex.count)", detail: "\(Set(model.codex.map(\.project)).count) projects · local metadata", symbol: "terminal", tint: PulseStyle.violet)
            }
            Surface(title: "Your week", subtitle: "ACTIVE HOURS") { WeeklyChart(days: Analytics.days(model.records, ending: model.now)) }
            HStack(alignment: .top, spacing: 18) {
                Surface(title: "Most-used applications", subtitle: "TODAY") {
                    if model.apps.isEmpty { EmptyState(title: "Nothing recorded yet", detail: "Enable monitoring in Settings to start your history.") }
                    ForEach(model.apps.prefix(4)) { AppRow(app: $0, total: model.todaySeconds) }
                }
                Surface(title: "System pulse", subtitle: "NOW") {
                    HStack(spacing: 24) { UsageRing(value: model.system.cpu ?? 0, label: "CPU", available: model.system.cpu != nil); UsageRing(value: model.system.memoryRatio, label: "MEMORY", tint: PulseStyle.violet, available: model.system.memoryAvailable); Spacer() }
                    PerformanceChart(points: model.chartHistory).frame(height: 94)
                    Text("CPU & memory · last 10 minutes").font(.caption2).foregroundStyle(.secondary)
                }
            }
            RecentActivity(model: model)
        }
    }
}
struct ScreenTimePage: View {
    @ObservedObject var model: AppModel
    @State private var range = 7
    var body: some View {
        VStack(spacing: 22) {
            HStack { MetricCard(title: "Today", value: Analytics.duration(model.todaySeconds), detail: "Active foreground time", symbol: "sun.max"); MetricCard(title: "Last 7 days", value: Analytics.duration(Analytics.days(model.records, ending: model.now).reduce(0) { $0 + $1.seconds }), detail: "Idle and sleep time excluded", symbol: "calendar", tint: PulseStyle.violet) }
            Picker("History", selection: $range) { Text("Week").tag(7); Text("Month").tag(30) }.pickerStyle(.segmented).frame(width: 220)
            Surface(title: "Daily activity", subtitle: "HOURS") { WeeklyChart(days: Analytics.days(model.records, ending: model.now, count: range)) }
            Surface(title: "Today's rhythm", subtitle: "APP ACTIVITY") {
                if model.todaySeconds == 0 { EmptyState(title: "Your timeline is empty", detail: "Only activity recorded after monitoring is enabled appears here.") }
                else {
                    Chart(model.records.filter { $0.overlap(from: model.today, to: model.tomorrow) > 0 }) { record in
                        BarMark(xStart: .value("Start", max(record.start, model.today)), xEnd: .value("End", min(record.end, model.tomorrow)), y: .value("Application", record.appName))
                            .foregroundStyle(PulseStyle.blue).cornerRadius(3)
                    }.chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { _ in AxisValueLabel(format: .dateTime.hour()) } }.frame(height: 170)
                }
            }
            Surface(title: "Category balance", subtitle: "TODAY") {
                ForEach(ActivityCategory.allCases) { category in
                    let seconds = model.apps.filter { $0.category == category }.reduce(0) { $0 + $1.seconds }
                    if seconds > 0 { HStack { Text(category.rawValue).font(.caption); Spacer(); Text(Analytics.duration(seconds)).font(.caption).monospacedDigit(); Text("\(Int(seconds / max(1, model.todaySeconds) * 100))%").font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing) } }
                }
            }
        }
    }
}
struct CodexPage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            Surface(title: "Subscription usage", subtitle: "OFFICIAL SOURCE REQUIRED") {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "info.circle").font(.title2).foregroundStyle(PulseStyle.violet)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Subscription usage unavailable").font(.title3.weight(.semibold))
                        Text("Local token counts do not represent your ChatGPT plan allowance. Reset windows and usage alerts are unavailable without a trustworthy authenticated source.").font(.caption).foregroundStyle(.secondary)
                        Link("Open official Codex usage settings ↗", destination: URL(string: "https://chatgpt.com/codex/settings/usage")!).font(.caption)
                    }
                }
            }
            if model.preferences.demo {
                Surface(title: "Illustrative usage window", subtitle: "DEMONSTRATION DATA") {
                    HStack { Text("28% used").font(.title3.weight(.semibold)); Spacer(); Text("Sample reset in").font(.caption).foregroundStyle(.secondary); Text(model.sessionStart.addingTimeInterval(7200), style: .timer).font(.caption).monospacedDigit() }
                    ProgressView(value: 0.28).tint(PulseStyle.violet)
                    Text("Fictional allowance for exploring the interface. This is not a plan limit or an authenticated usage reading. Usage notifications are not sent.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack { MetricCard(title: "Local sessions", value: "\(model.codex.count)", detail: "Metadata only · no session contents", symbol: "terminal", tint: PulseStyle.violet); MetricCard(title: "Projects", value: "\(Set(model.codex.map(\.project)).count)", detail: "Separate from foreground screen time", symbol: "folder", tint: PulseStyle.cyan) }
            Surface(title: "Project activity", subtitle: "SESSION SPAN, NOT ACTIVE TIME") {
                let grouped = Dictionary(grouping: model.codex, by: \.project)
                ForEach(grouped.keys.sorted(), id: \.self) { project in
                    HStack { Label(project, systemImage: "folder").font(.caption); Spacer(); Text("\(grouped[project]?.count ?? 0) sessions").font(.caption).foregroundStyle(.secondary); Text(Analytics.duration(grouped[project]?.reduce(0) { $0 + $1.duration } ?? 0)).font(.caption).monospacedDigit() }
                }
                if model.codex.isEmpty { EmptyState(title: "Connect your local sessions", detail: "Choose your Codex sessions folder to import metadata. No credentials are needed.") }
            }
            Surface(title: "Recent Codex sessions") {
                if !model.preferences.demo { Button(model.importing ? "Importing…" : "Import local session metadata…") { model.importCodex() }.disabled(model.importing) }
                ForEach(model.codex.prefix(30)) { session in
                    HStack {
                        Image(systemName: "terminal").foregroundStyle(PulseStyle.violet)
                        VStack(alignment: .leading, spacing: 4) { Text(session.project).font(.system(size: 13, weight: .medium)); Text(session.date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) { Text(Analytics.duration(session.duration) + " span").font(.caption); Text(session.inputTokens.map { "\($0.formatted()) input · \((session.outputTokens ?? 0).formatted()) output tokens" } ?? "Token statistics unavailable").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5)
                }
            }
        }
    }
}
struct ApplicationsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var days = 1
    var body: some View {
        VStack(spacing: 22) {
            Picker("Period", selection: $days) { Text("Today").tag(1); Text("Week").tag(7); Text("Month").tag(30) }.pickerStyle(.segmented).frame(width: 280)
            Surface(title: "Application breakdown", subtitle: "CATEGORIES ARE EDITABLE") {
                let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: model.today)!
                let apps = Analytics.applications(model.records, from: start, to: model.tomorrow)
                if apps.isEmpty { EmptyState(title: "No applications recorded", detail: "Enable monitoring in Settings, then use your Mac normally.") }
                ForEach(apps) { app in
                    VStack(alignment: .leading, spacing: 8) {
                        AppRow(app: app, total: apps.reduce(0) { $0 + $1.seconds })
                        HStack {
                            Text("\(app.sessions) activity periods · last active \(app.lastActive.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Picker("Category", selection: Binding(get: { preferences.category(for: app.bundleID) }, set: { preferences.categories[app.bundleID] = $0.rawValue })) {
                                ForEach(ActivityCategory.allCases) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().frame(width: 160)
                        }.padding(.leading, 44)
                        Divider().opacity(0.3)
                    }
                }
            }
        }
    }
}
struct SystemPage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            HStack {
                MetricCard(title: "CPU", value: percent(model.system.cpu), detail: "\(ProcessInfo.processInfo.processorCount) logical processors", symbol: "cpu")
                MetricCard(title: "Memory estimate", value: model.system.memoryAvailable ? bytes(model.system.memory) : "—", detail: "of \(bytes(model.system.totalMemory)) physical memory", symbol: "memorychip", tint: PulseStyle.violet)
                MetricCard(title: "Battery", value: percent(model.system.battery), detail: model.system.battery == nil ? "No battery reported" : (model.system.charging ? "Charging" : "On battery"), symbol: "battery.75percent", tint: PulseStyle.cyan)
            }
            Surface(title: "Performance history", subtitle: "CPU BLUE · MEMORY VIOLET") { PerformanceChart(points: model.chartHistory) }
            Surface(title: "Storage", subtitle: "HOME VOLUME") {
                HStack { Text(model.system.storageAvailable ? bytes(max(0, model.system.storageTotal - model.system.storageFree)) + " used" : "Storage unavailable").font(.title3.weight(.semibold)); Spacer(); Text(model.system.storageAvailable ? bytes(model.system.storageFree) + " available" : "—").font(.caption).foregroundStyle(.secondary) }
                ProgressView(value: model.system.storageTotal > 0 ? 1 - model.system.storageFree / model.system.storageTotal : 0).tint(PulseStyle.violet)
            }
            HStack {
                MetricCard(title: "Download", value: model.system.download.map { bytes($0) + "/s" } ?? "—", detail: "All active non-loopback interfaces", symbol: "arrow.down", tint: PulseStyle.cyan)
                MetricCard(title: "Upload", value: model.system.upload.map { bytes($0) + "/s" } ?? "—", detail: "Interface counters, sampled every 5s", symbol: "arrow.up")
                MetricCard(title: "Uptime", value: Analytics.duration(model.system.uptime), detail: "Since the last system boot", symbol: "power", tint: PulseStyle.violet)
            }
            Text("Memory is estimated from active, wired and compressed pages. Memory pressure, GPU, temperature, battery health and cycle counts are unavailable in this proof of concept. The chart shows 10 minutes; one sample per minute is stored while live monitoring is enabled, subject to your retention setting.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct RecentActivity: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Surface(title: "Recent activity", subtitle: "FOREGROUND PERIODS") {
            if model.records.isEmpty { EmptyState(title: "A fresh start", detail: "Your activity history will appear here after monitoring is enabled.") }
            ForEach(model.records.sorted { $0.start > $1.start }.prefix(5)) { record in ActivityTimelineRow(record: record) }
        }
    }
}
struct ActivityTimelineRow: View {
    let record: ActivityRecord
    var body: some View {
        HStack(spacing: 14) {
            ApplicationIcon(bundle: record.bundleID)
            VStack(alignment: .leading, spacing: 5) { Text(record.appName).font(.system(size: 13, weight: .medium)); Text(record.category.rawValue).font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) { Text(Analytics.duration(record.duration)).font(.caption).monospacedDigit(); Text(record.start, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
}
struct SessionsPage: View {
    @ObservedObject var model: AppModel
    @State private var application = "All applications"
    @State private var date = Date()
    @State private var filterDate = false
    var filtered: [ActivityRecord] { model.records.filter { (application == "All applications" || $0.appName == application) && (!filterDate || Calendar.current.isDate($0.start, inSameDayAs: date)) }.sorted { $0.start > $1.start } }
    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Picker("Application", selection: $application) { Text("All applications").tag("All applications"); ForEach(Set(model.records.map(\.appName)).sorted(), id: \.self) { Text($0).tag($0) } }.frame(width: 250)
                Spacer(); Toggle("Filter date", isOn: $filterDate).toggleStyle(.checkbox)
                DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden().disabled(!filterDate)
            }
            Surface(title: "Session events", subtitle: "LAUNCH · IDLE · SLEEP · WAKE") {
                if model.preferences.demo {
                    HStack { Label("Wake", systemImage: "sunrise"); Spacer(); Text("Today, 9:00 AM · sample event").foregroundStyle(.secondary) }.font(.caption)
                } else if model.events.isEmpty { Text("Events appear while live monitoring is enabled.").font(.caption).foregroundStyle(.secondary) }
                else {
                    ForEach(model.events.filter { (!filterDate || Calendar.current.isDate($0.date, inSameDayAs: date)) && (application == "All applications" || $0.application == application) }.prefix(50)) { event in
                        HStack { Text(event.kind + (event.application.map { " · " + $0 } ?? "")); Spacer(); Text(event.date, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary) }.font(.caption).padding(.vertical, 3)
                    }
                }
            }
            Surface(title: "Activity timeline", subtitle: "\(filtered.count) PERIODS") {
                if filtered.isEmpty { EmptyState(title: "No matching activity", detail: "Try another filter or enable monitoring.") }
                ForEach(filtered.prefix(200)) { record in ActivityTimelineRow(record: record) }
                if filtered.count > 200 { Text("Showing the most recent 200 periods. Export CSV for the full retained history.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
#endif
