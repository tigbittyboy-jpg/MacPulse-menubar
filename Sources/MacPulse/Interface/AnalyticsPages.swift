#if os(macOS)
import SwiftUI
import Charts
import MacPulseCore

struct OverviewPage: View {
    @ObservedObject var model: AppModel
    @State private var range = 7
    private var source: DataSourceState { model.source }
    private var days: [ObservedDay] { HistoryAnalytics.daily(records: model.records, sessions: model.sessions, intervals: model.intervals, ending: model.now, count: 7) }
    private var average: Double? { let known = days.compactMap(\.seconds); return known.isEmpty ? nil : known.reduce(0, +) / Double(known.count) }
    private var yesterday: Double? { days.dropLast().last?.seconds }
    private var development: Double { model.apps.filter { $0.category == .development }.reduce(0) { $0 + $1.seconds } }
    var body: some View {
        VStack(spacing: 18) {
            Surface(title: "Right now", subtitle: model.sessionState.uppercased()) {
                HStack(spacing: 15) {
                    ApplicationIcon(bundle: model.preferences.demo ? "com.apple.dt.Xcode" : model.activeBundle)
                    VStack(alignment: .leading, spacing: 5) { Text(model.preferences.demo ? "Xcode" : model.activeApp).font(.headline); Text(Analytics.duration(model.currentAppSeconds) + " in the current application period").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); SourceBadge(source: model.preferences.demo ? .demo : .live)
                    VStack(alignment: .trailing, spacing: 5) { Text(Analytics.duration(model.sessionSeconds)).font(.title3.weight(.semibold)).monospacedDigit(); Text("current session active time").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                MetricCard(title: "Screen time today", value: Analytics.duration(model.todaySeconds), detail: average.map { "7-day observed average " + Analytics.duration($0) } ?? "No observed daily average yet", symbol: "hourglass", source: days.last?.seconds == nil ? .unavailable : source, context: "Session " + Analytics.duration(model.sessionSeconds), trend: yesterday.map { (model.todaySeconds >= $0 ? "+" : "−") + Analytics.duration(abs(model.todaySeconds - $0)) + " vs yesterday's recorded time" })
                MetricCard(title: "Development today", value: Analytics.duration(development), detail: "\(model.codex.count) retained Codex sessions · \(HistoryAnalytics.topProject(model.codex) ?? "no project metadata")", symbol: "terminal", tint: PulseStyle.violet, source: days.last?.seconds == nil ? .unavailable : source, context: "This week: " + Analytics.duration(model.records.filter { $0.category == .development }.reduce(0) { $0 + $1.overlap(from: days.first?.date ?? model.today, to: model.tomorrow) }))
                MetricCard(title: "System pulse", value: percent(model.system.cpu), detail: model.system.memoryAvailable ? "Memory " + percent(model.system.memoryRatio) + " · Battery " + percent(model.system.battery) : "Memory reading unavailable", symbol: "cpu", tint: PulseStyle.cyan, source: model.preferences.demo ? .demo : (model.system.cpu == nil ? .unavailable : .live), context: "Pressure: " + (model.preferences.demo ? "Normal · sample" : model.memoryPressure), samples: model.chartHistory.suffix(20).map { $0.cpu * 100 }, size: .compact)
                MetricCard(title: "Top application", value: model.apps.first?.name ?? "—", detail: "\(model.apps.count) apps today · \(model.sessions.first?.switches ?? 0) switches in latest session", symbol: "app.badge", source: model.apps.isEmpty ? .unavailable : source, context: "Longest period " + (model.records.filter { $0.overlap(from: model.today, to: model.tomorrow) > 0 }.map { $0.overlap(from: model.today, to: model.tomorrow) }.max().map(Analytics.duration) ?? "unavailable"), size: .compact)
            }
            Surface(title: "Today's rhythm", subtitle: "LOCAL DAY · RECORDED INTERVALS") { DayTimeline(records: model.records, intervals: model.intervals, date: model.today) }
            Surface(title: "Activity by category", subtitle: "HOURS") {
                Picker("Overview date range", selection: $range) { Text("7 days").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented).frame(width: 200)
                StackedActivityChart(records: model.records, sessions: model.sessions, intervals: model.intervals, ending: model.now, days: range)
            }
            HStack(alignment: .top, spacing: 18) {
                Surface(title: "Top five applications", subtitle: "TODAY") {
                    if model.apps.isEmpty { EmptyState(title: "No recorded activity today", detail: "Enable monitoring to begin recording. Existing history is preserved.") }
                    ForEach(model.apps.prefix(5)) { AppRow(app: $0, total: model.todaySeconds) }
                }
                Surface(title: "Recent computer sessions", subtitle: source.rawValue.uppercased()) {
                    if model.sessions.isEmpty { EmptyState(title: "New session history starts here", detail: "Session boundaries are recorded by this upgrade. Earlier application history is preserved.") }
                    ForEach(model.sessions.prefix(3)) { SessionSummaryRow(session: $0, records: model.records) }
                }
            }
        }
    }
}
struct ScreenTimePage: View {
    @ObservedObject var model: AppModel
    @State private var ending = Date()
    @State private var range = 7
    @State private var application = "All applications"
    @State private var category = "All categories"
    private var filtered: [ActivityRecord] { model.records.filter { (application == "All applications" || $0.bundleID == application) && (category == "All categories" || $0.category.rawValue == category) } }
    private var start: Date { Calendar.current.startOfDay(for: ending) }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: start)! }
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                DatePicker("Ending date", selection: $ending, in: ...Date(), displayedComponents: .date)
                Spacer(); Picker("Range", selection: $range) { Text("Week").tag(7); Text("Month").tag(30) }.pickerStyle(.segmented).frame(width: 180)
            }
            HStack {
                Picker("Application", selection: $application) { Text("All applications").tag("All applications"); ForEach(Analytics.applications(model.records, from: .distantPast, to: .distantFuture)) { Text($0.name).tag($0.bundleID) } }
                Picker("Category", selection: $category) { Text("All categories").tag("All categories"); ForEach(ActivityCategory.allCases) { Text($0.rawValue).tag($0.rawValue) } }
            }
            let usage = Analytics.applications(filtered, from: start, to: end)
            let days = HistoryAnalytics.daily(records: filtered, sessions: model.sessions, intervals: model.intervals, ending: ending, count: range)
            let known = days.compactMap(\.seconds)
            HStack {
                MetricCard(title: "Selected day", value: Analytics.duration(usage.reduce(0) { $0 + $1.seconds }), detail: start.formatted(date: .abbreviated, time: .omitted), symbol: "calendar", source: days.last?.seconds == nil ? .unavailable : model.source)
                MetricCard(title: "Recorded range", value: Analytics.duration(known.reduce(0, +)), detail: "\(known.count) observed days · unobserved days excluded", symbol: "chart.bar", tint: PulseStyle.violet, source: known.isEmpty ? .unavailable : model.source)
                MetricCard(title: "Observed-day average", value: known.isEmpty ? "—" : Analytics.duration(known.reduce(0, +) / Double(known.count)), detail: "Partial-day observations are included", symbol: "divide", tint: PulseStyle.cyan, source: known.isEmpty ? .unavailable : model.source)
            }
            Surface(title: "Daily category totals", subtitle: "RECORDED ACTIVE HOURS") { StackedActivityChart(records: filtered, sessions: model.sessions, intervals: model.intervals, ending: ending, days: range) }
            Surface(title: "Selected-day timeline", subtitle: "ACTIVE · IDLE · SLEEP") { DayTimeline(records: filtered, intervals: model.intervals, date: ending) }
            Surface(title: "Application breakdown", subtitle: "SELECTED DAY") { ForEach(usage) { AppRow(app: $0, total: usage.reduce(0) { $0 + $1.seconds }) } }
        }
    }
}
struct InsightsPage: View {
    @ObservedObject var model: AppModel
    @State private var ending = Date()
    private var recap: WeeklyRecap { HistoryAnalytics.recap(records: model.records, sessions: model.sessions, codex: model.codex, intervals: model.intervals, ending: ending) }
    var body: some View {
        let summary = recap
        VStack(spacing: 18) {
            HStack { DatePicker("Seven days ending", selection: $ending, in: ...Date(), displayedComponents: .date); Spacer(); SourceBadge(source: model.source); Button("Export recap…") { model.export(format: ReportExportKind.weekly.rawValue, ending: ending) } }
            if summary.recordedDays == 0 { EmptyState(title: "Insights need recorded activity", detail: "Enable monitoring or choose a date range with observations. Missing history is never treated as zero.") }
            else {
                HStack {
                    MetricCard(title: "Active time", value: Analytics.duration(summary.total), detail: "\(summary.recordedDays) of 7 days observed", symbol: "hourglass", source: model.source, trend: summary.previousTotal.map { (summary.total >= $0 ? "+" : "−") + Analytics.duration(abs(summary.total - $0)) + " vs preceding recorded week" })
                    MetricCard(title: "Top application", value: summary.topApp ?? "—", detail: "Across the selected seven days", symbol: "app", tint: PulseStyle.violet, source: model.source)
                    MetricCard(title: "Codex sessions", value: "\(summary.codexSessions)", detail: "Session metadata · separate from screen time", symbol: "terminal", tint: PulseStyle.cyan, source: model.source)
                }
                Surface(title: "Your weekly recap", subtitle: "FACTS FROM LOCAL OBSERVATIONS") {
                    if let day = summary.mostActiveDay, let seconds = day.seconds { Label("Your most active recorded day was " + day.date.formatted(.dateTime.weekday(.wide)) + ", with " + Analytics.duration(seconds) + ".", systemImage: "calendar").font(.callout) }
                    ForEach(ActivityCategory.allCases) { category in
                        if let seconds = summary.categories[category], seconds > 0 {
                            HStack { Circle().fill(PulseStyle.category(category)).frame(width: 7, height: 7); Text(category.rawValue).font(.callout); Spacer(); Text(Analytics.duration(seconds)).monospacedDigit(); Text("\(Int(seconds / max(1, summary.total) * 100))%").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing) }.font(.caption)
                        }
                    }
                    if let average = summary.averageSession { Text("Completed sessions averaged " + Analytics.duration(average) + " of active time.").font(.callout) }
                    if summary.previousTotal == nil { Text("Week-to-week comparison needs observations on all seven days of both ranges. No comparison is inferred from missing history.").font(.caption).foregroundStyle(.secondary) }
                }
                Surface(title: "Personal records", subtitle: "RETAINED HISTORY ONLY") {
                    let activeSession = model.sessions.max { $0.activeSeconds < $1.activeSeconds }
                    let longestApp = model.records.max { $0.duration < $1.duration }
                    let development = model.sessions.map { session in model.records.filter { $0.category == .development }.reduce(0) { $0 + $1.overlap(from: session.start, to: session.end ?? session.observedUntil) } }.max()
                    LabeledContent("Longest recorded active session", value: activeSession.map { Analytics.duration($0.activeSeconds) } ?? "Unavailable")
                    LabeledContent("Most development time in a session", value: development.map(Analytics.duration) ?? "Unavailable")
                    LabeledContent("Longest application period", value: longestApp.map { $0.appName + " · " + Analytics.duration($0.duration) } ?? "Unavailable")
                    Text("These records cover retained observations, not your lifetime computer usage. No productivity score or psychological interpretation is assigned.").font(.caption).foregroundStyle(.secondary)
                }
                Surface(title: "Selected week", subtitle: "ACTIVE HOURS BY CATEGORY") { StackedActivityChart(records: model.records, sessions: model.sessions, intervals: model.intervals, ending: ending) }
            }
        }
    }
}
struct SessionsPage: View {
    @ObservedObject var model: AppModel
    @State private var date = Date()
    @State private var filterDate = false
    @State private var selected: ComputerSession?
    @State private var application = "All applications"
    private var filtered: [ComputerSession] {
        model.sessions.filter { session in
            (!filterDate || Calendar.current.isDate(session.start, inSameDayAs: date)) && (application == "All applications" || model.records.contains { $0.bundleID == application && $0.overlap(from: session.start, to: session.end ?? session.observedUntil) > 0 })
        }
    }
    var body: some View {
        VStack(spacing: 18) {
            HStack { Toggle("Filter date", isOn: $filterDate).toggleStyle(.checkbox); DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden().disabled(!filterDate); Spacer(); Button("Export sessions…") { model.export(format: ReportExportKind.sessions.rawValue) } }
            Picker("Application", selection: $application) { Text("All applications").tag("All applications"); ForEach(Analytics.applications(model.records, from: .distantPast, to: .distantFuture)) { Text($0.name).tag($0.bundleID) } }.frame(maxWidth: 340, alignment: .leading)
            HStack {
                MetricCard(title: "Computer sessions", value: "\(filtered.count)", detail: "Tracked while MacPulse monitoring was enabled", symbol: "clock", source: filtered.isEmpty ? .unavailable : model.source)
                MetricCard(title: "Active time", value: Analytics.duration(filtered.reduce(0) { $0 + $1.activeSeconds }), detail: "Sleep and detected idle excluded", symbol: "record.circle", tint: PulseStyle.cyan, source: filtered.isEmpty ? .unavailable : model.source)
                MetricCard(title: "Idle time", value: Analytics.duration(filtered.reduce(0) { $0 + $1.idleSeconds }), detail: "Past the configured idle threshold", symbol: "pause.circle", tint: PulseStyle.violet, source: filtered.isEmpty ? .unavailable : model.source)
            }
            Surface(title: "Computer session history", subtitle: "SELECT A SESSION FOR DETAILS") {
                if filtered.isEmpty { EmptyState(title: "No matching computer sessions", detail: "Explicit session tracking starts with this upgrade. Prior application intervals remain in Screen Time.") }
                ForEach(filtered.prefix(100)) { session in Button { selected = session } label: { SessionSummaryRow(session: session, records: model.records) }.buttonStyle(.plain).accessibilityLabel("Session " + session.start.formatted()) }
            }
            if !model.events.isEmpty && !model.preferences.demo {
                Surface(title: "Recent lifecycle events", subtitle: "OBSERVED EVENTS") {
                    ForEach(model.events.prefix(20)) { event in HStack { Text(event.kind + (event.application.map { " · " + $0 } ?? "")); Spacer(); Text(event.date, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary) }.font(.caption).padding(.vertical, 3) }
                }
            }
        }.sheet(item: $selected) { session in
            let records = model.records.filter { $0.overlap(from: session.start, to: session.end ?? session.observedUntil) > 0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("Session details").font(.title2.weight(.semibold)); Spacer(); Button("Done") { selected = nil } }
                    Text(session.start.formatted() + " – " + (session.end?.formatted() ?? "In progress")).font(.caption).foregroundStyle(.secondary)
                    HStack { Label(Analytics.duration(session.activeSeconds) + " active", systemImage: "record.circle"); Spacer(); Label(Analytics.duration(session.idleSeconds) + " idle", systemImage: "pause"); Spacer(); Label("\(session.switches) switches", systemImage: "arrow.triangle.swap") }.font(.caption)
                    Text("Sleep interruptions: " + Analytics.duration(session.sleepSeconds) + " · " + (session.endReason ?? "Recording")).font(.caption).foregroundStyle(.secondary)
                    DayTimeline(records: records, intervals: model.intervals.filter { $0.sessionID == session.id }, date: session.start)
                    Text("Application breakdown").font(.headline)
                    let apps = Analytics.applications(records, from: session.start, to: session.end ?? session.observedUntil)
                    ForEach(apps) { AppRow(app: $0, total: session.activeSeconds) }
                }.padding(28)
            }.frame(width: 720, height: 580)
        }
    }
}
#endif
