#if os(macOS)
import SwiftUI
import Charts
import MacPulseCore

struct CodexPage: View {
    @ObservedObject var model: AppModel
    @State private var days = 7
    var body: some View {
        VStack(spacing: 18) {
            subscriptionCard
            summaryCards
            historyCard
            projectCard
            modelCard
            usageHistoryCard
            recentCard
        }
    }
    @ViewBuilder private var subscriptionCard: some View {
    Surface(title: "Subscription allowance", subtitle: model.usageSource.rawValue.uppercased()) {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.currentUsage == nil ? "Subscription usage unavailable" : (model.usageSource == .historical ? "Last recorded allowance · stale" : "Reported usage windows")).font(.headline)
                Text(model.preferences.demo ? "Illustrative values, not a real plan allowance." : model.usageStatus).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.preferences.demo { Button(model.refreshingUsage ? "Refreshing…" : "Refresh usage") { model.refreshUsage() }.disabled(model.refreshingUsage || model.preferences.usageExecutable.isEmpty) }
        }
        if let reading = model.currentUsage {
            if let allowed = reading.ordinaryUsageAllowed { Text(allowed ? "Backend reports included usage is permitted." : "Backend reports included usage is currently restricted.").font(.caption).foregroundStyle(allowed ? Color.secondary : Color.orange) }
            ForEach(reading.windows) { window in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(window.name).font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(Int(window.usedPercent))% used · \(Int(window.remainingPercent))% remaining").font(.caption).monospacedDigit() }
                    ProgressView(value: window.usedPercent / 100).tint(window.usedPercent >= 95 ? .red : (window.usedPercent >= 80 ? .orange : PulseStyle.violet))
                    HStack { Text(window.durationMinutes.map { "Reported window: \($0) minutes" } ?? "Window duration unavailable"); Spacer(); Text("Reset: " + SampleMath.resetCountdown(reset: window.resetsAt, now: model.now)) }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    if model.usageSource == .live, let projection = UsageParser.projectedExhaustion(window: window, history: model.usageHistory, now: model.now) {
                        Text("Estimated exhaustion at " + projection.formatted(date: .abbreviated, time: .shortened) + " if the recently observed rate continues. Reset is " + (window.resetsAt?.formatted(date: .abbreviated, time: .shortened) ?? "unknown") + ".").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5)
            }
            Text("Last successful refresh: " + reading.refreshedAt.formatted()).font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("Choose your installed Codex CLI in Settings and sign in through Codex itself. MacPulse makes a read-only official app-server request; it never reads auth files or browser cookies.").font(.caption).foregroundStyle(.secondary)
        }
        Link("Open official Codex usage settings ↗", destination: URL(string: "https://chatgpt.com/codex/settings/usage")!).font(.caption)
    }
    }
    @ViewBuilder private var summaryCards: some View {
    HStack {
        MetricCard(title: "Local sessions", value: "\(model.codex.count)", detail: "Retained metadata · separate from plan allowance", symbol: "terminal", tint: PulseStyle.violet, source: model.codex.isEmpty ? .unavailable : model.source)
        MetricCard(title: "Projects", value: "\(Set(model.codex.map(\.project)).count)", detail: "Most active: " + (HistoryAnalytics.topProject(model.codex) ?? "Unavailable"), symbol: "folder", tint: PulseStyle.cyan, source: model.codex.isEmpty ? .unavailable : model.source)
        MetricCard(title: "Reported input tokens", value: model.codex.compactMap(\.inputTokens).reduce(0, +).formatted(), detail: "Available session counts only · not API billing", symbol: "number", source: model.codex.contains { $0.inputTokens != nil } ? model.source : .unavailable)
    }
    }
    @ViewBuilder private var historyCard: some View {
    Surface(title: "Local session history", subtitle: "COUNTS BY START DATE") {
        Picker("Codex range", selection: $days) { Text("7 days").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented).frame(width: 200)
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: model.today)!
        let grouped = Dictionary(grouping: model.codex.filter { $0.date >= start && $0.date < model.tomorrow }, by: { Calendar.current.startOfDay(for: $0.date) })
        if grouped.isEmpty { EmptyState(title: "No session metadata in this range", detail: "Import your local Codex sessions in Live mode.") }
        else {
            Chart(grouped.keys.sorted(), id: \.self) { date in BarMark(x: .value("Day", date, unit: .day), y: .value("Sessions", grouped[date]?.count ?? 0)).foregroundStyle(PulseStyle.violet).cornerRadius(4) }.chartXAxis { AxisMarks(values: .stride(by: .day, count: days > 7 ? 5 : 1)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }.frame(height: 150).accessibilityLabel("Imported local Codex sessions by their start date")
        }
    }
    }
    @ViewBuilder private var projectCard: some View {
    Surface(title: "Project leaderboard", subtitle: "LOCAL METADATA · SESSION SPAN") {
        let projects = Dictionary(grouping: model.codex, by: \.project)
        ForEach(projects.keys.sorted { (projects[$0]?.count ?? 0) > (projects[$1]?.count ?? 0) }, id: \.self) { project in
            let sessions = projects[project] ?? []
            VStack(alignment: .leading, spacing: 6) {
                HStack { Label(project, systemImage: "folder").font(.system(size: 13, weight: .medium)); Spacer(); Text("\(sessions.count) sessions · " + Analytics.duration(sessions.reduce(0) { $0 + $1.duration }) + " span").font(.caption).monospacedDigit() }
                HStack { Text("Last event: " + (sessions.map(\.lastEvent).max()?.formatted() ?? "Unavailable")); Spacer(); Text("Input tokens: " + (sessions.contains { $0.inputTokens != nil } ? sessions.compactMap(\.inputTokens).reduce(0, +).formatted() : "Unavailable")) }.font(.caption2).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
        Text("Session span includes gaps between events. It is not measured foreground development time. Project-level active time attribution is unavailable; projects use basenames for privacy.").font(.caption).foregroundStyle(.secondary)
    }
    }
    @ViewBuilder private var modelCard: some View {
    Surface(title: "Model statistics", subtitle: "LAST REPORTED MODEL PER SESSION") {
        let groups = Dictionary(grouping: model.codex, by: { $0.model ?? "Model unavailable" })
        ForEach(groups.keys.sorted(), id: \.self) { name in
            let values = groups[name] ?? []
            HStack { Text(name).font(.caption); Spacer(); Text("\(values.count) sessions").font(.caption); Text("\(Int(Double(values.count) / Double(max(1, model.codex.count)) * 100))% of sessions").font(.caption).foregroundStyle(.secondary) }
        }
        Text("A session can use multiple models. Aggregate session tokens cannot reliably be attributed to each model, so no per-model token distribution is invented.").font(.caption2).foregroundStyle(.secondary)
    }
    }
    @ViewBuilder private var usageHistoryCard: some View {
    if !model.usageHistory.isEmpty && !model.preferences.demo {
        Surface(title: "Recorded subscription readings", subtitle: "POINTS · NO INFERRED HISTORY") {
            let readings = Array(model.usageHistory.prefix(200))
            Chart { ForEach(readings) { reading in ForEach(reading.windows) { window in PointMark(x: .value("Refresh", reading.refreshedAt), y: .value("Used %", window.usedPercent)).foregroundStyle(by: .value("Window", window.name)) } } }.chartYScale(domain: 0...100).frame(height: 160)
        }
    }
    }
    @ViewBuilder private var recentCard: some View {
    Surface(title: "Recent sessions", subtitle: model.importStatus.uppercased()) {
        HStack { if !model.preferences.demo { Button(model.importing ? "Importing…" : "Import metadata…") { model.importCodex() }.disabled(model.importing) }; Spacer(); Button("Export metadata…") { model.export(format: ReportExportKind.codex.rawValue) } }
        ForEach(Array(model.codex.sorted { $0.lastEvent > $1.lastEvent }.prefix(30))) { session in
            CodexSessionRow(session: session)
        }
    }
    }
}
private struct CodexSessionRow: View {
    let session: CodexSession
    private var tokenDescription: String {
        let input = session.inputTokens?.formatted() ?? "—"
        let output = session.outputTokens?.formatted() ?? "—"
        let cached = session.cachedTokens?.formatted() ?? "—"
        return "Input \(input) · Output \(output) · Cached input \(cached)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.project).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(Analytics.duration(session.duration) + " session span").font(.caption).monospacedDigit()
            }
            HStack {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text(session.model ?? "Model unavailable")
            }.font(.caption2).foregroundStyle(.secondary)
            Text(tokenDescription).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            Divider().opacity(0.4)
        }
    }
}
struct ApplicationsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var days = 1
    @State private var sort = "Duration"
    private var details: [ApplicationDetail] {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: model.today)!
        let values = HistoryAnalytics.applicationDetails(model.records, from: start, to: model.tomorrow)
        switch sort {
        case "Name": return values.sorted { $0.usage.name.localizedCaseInsensitiveCompare($1.usage.name) == .orderedAscending }
        case "Last used": return values.sorted { $0.usage.lastActive > $1.usage.lastActive }
        case "Periods": return values.sorted { $0.usage.sessions > $1.usage.sessions }
        default: return values
        }
    }
    var body: some View {
        VStack(spacing: 18) {
            HStack { Picker("Period", selection: $days) { Text("Today").tag(1); Text("Week").tag(7); Text("Month").tag(30) }.pickerStyle(.segmented).frame(width: 270); Spacer(); Picker("Sort", selection: $sort) { ForEach(["Duration", "Name", "Last used", "Periods"], id: \.self) { Text($0) } }.frame(width: 170) }
            Surface(title: "Application analytics", subtitle: "\(details.count) APPS · RECORDED ACTIVE TIME") {
                if details.isEmpty { EmptyState(title: "No applications recorded in this range", detail: "Only observed intervals are shown; no OS Screen Time history is imported.") }
                ForEach(details) { detail in
                    let app = detail.usage
                    VStack(alignment: .leading, spacing: 8) {
                        AppRow(app: app, total: details.reduce(0) { $0 + $1.usage.seconds })
                        HStack {
                            Text("\(app.sessions) periods · Average " + Analytics.duration(detail.average) + " · Longest " + Analytics.duration(detail.longest)).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Picker("Category for " + app.name, selection: Binding(get: { preferences.categories[app.bundleID].flatMap(ActivityCategory.init(rawValue:)) ?? app.category }, set: { preferences.categories[app.bundleID] = $0.rawValue })) { ForEach(ActivityCategory.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 160)
                        }.padding(.leading, 44)
                        Text("Last active: " + app.lastActive.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 44)
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }
}
struct SystemPage: View {
    @ObservedObject var model: AppModel
    @State private var range = "Live"
    private var points: [PerformancePoint] {
        if range == "Live" || model.preferences.demo { return model.chartHistory }
        let cutoff = model.now.addingTimeInterval(range == "1 hour" ? -3600 : -86400)
        return model.savedSamples.filter { $0.date >= cutoff }.reversed().map { PerformancePoint(date: $0.date, cpu: $0.cpu, memory: $0.memoryRatio, upload: $0.upload, download: $0.download) }
    }
    private var systemSource: DataSourceState { model.preferences.demo ? .demo : .live }
    var body: some View {
        VStack(spacing: 18) {
            HStack { Text(model.system.processorName).font(.caption).foregroundStyle(.secondary); Spacer(); Picker("Performance range", selection: $range) { ForEach(["Live", "1 hour", "24 hours"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 270) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                MetricCard(title: "CPU utilization", value: percent(model.system.cpu), detail: "\(model.preferences.demo ? 12 : ProcessInfo.processInfo.processorCount) logical processors · normalized total", symbol: "cpu", source: model.system.cpu == nil ? .unavailable : systemSource, context: "Recent average " + percent(points.isEmpty ? nil : points.reduce(0) { $0 + $1.cpu } / Double(points.count)) + " · Peak " + percent(points.map(\.cpu).max()), samples: points.suffix(30).map { $0.cpu * 100 })
                MetricCard(title: "Memory used estimate", value: bytes(model.system.memory), detail: model.system.memoryAvailable ? bytes(model.system.totalMemory) + " installed · " + bytes(max(0, model.system.totalMemory - model.system.memory)) + " estimated available" : "Memory usage unavailable · " + bytes(model.system.totalMemory) + " installed", symbol: "memorychip", tint: PulseStyle.violet, source: model.preferences.demo ? .demo : (model.system.memoryAvailable ? .estimated : .unavailable), context: "Pressure signal: " + (model.preferences.demo ? "Normal · sample" : model.memoryPressure))
                MetricCard(title: "Battery", value: percent(model.system.battery), detail: model.system.battery == nil ? "No battery source available" : (model.system.charging ? "Charging" : "Battery charge reported"), symbol: "battery.75percent", tint: PulseStyle.cyan, source: model.system.battery == nil ? .unavailable : systemSource, context: "Health and cycle count unavailable")
                MetricCard(title: "Storage used", value: model.system.storageAvailable && model.system.storageTotal > 0 ? percent(1 - model.system.storageFree / model.system.storageTotal) : "—", detail: model.system.storageAvailable ? bytes(model.system.storageFree) + " available of " + bytes(model.system.storageTotal) : "No volume capacity reading available", symbol: "internaldrive", source: model.system.storageAvailable ? systemSource : .unavailable, context: "Capacity for the home volume")
            }
            Surface(title: "CPU & memory history", subtitle: "BLUE CPU · VIOLET MEMORY · %") { PerformanceChart(points: points, gapTolerance: range == "Live" ? 20 : 90) }
            Surface(title: "Memory detail", subtitle: "CACHED MEMORY IS NOT A PRESSURE SCORE") {
                LabeledContent("Compressed memory", value: model.system.compressedMemory.map(bytes) ?? "Unavailable")
                LabeledContent("Swap used", value: model.system.swapUsed.map(bytes) ?? "Unavailable")
                Text("Used memory is estimated from active, wired and compressed pages. Pressure is a native system event signal and remains unavailable until the OS reports one.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                MetricCard(title: "Download", value: model.system.download.map { bytes($0) + "/s" } ?? "—", detail: bytes(model.system.transferredIn) + " observed since launch", symbol: "arrow.down", tint: PulseStyle.cyan, source: model.system.download == nil ? .unavailable : systemSource)
                MetricCard(title: "Upload", value: model.system.upload.map { bytes($0) + "/s" } ?? "—", detail: bytes(model.system.transferredOut) + " observed since launch", symbol: "arrow.up", source: model.system.upload == nil ? .unavailable : systemSource)
                MetricCard(title: "Uptime", value: Analytics.duration(model.system.uptime), detail: "Since system boot", symbol: "power", tint: PulseStyle.violet, source: systemSource)
            }
            Surface(title: "Recorded network rates", subtitle: "BYTES / SECOND · OBSERVED SAMPLE POINTS") {
                let values = points.filter { $0.download != nil || $0.upload != nil }
                if values.isEmpty { EmptyState(title: "No network rate samples", detail: "Enable live monitoring to retain minute samples, or select Live.") }
                else {
                    Chart(values) { point in
                        if let value = point.download { PointMark(x: .value("Time", point.date), y: .value("Bytes/s", value)).foregroundStyle(PulseStyle.cyan) }
                        if let value = point.upload { PointMark(x: .value("Time", point.date), y: .value("Bytes/s", value)).foregroundStyle(PulseStyle.blue) }
                    }.frame(height: 150).accessibilityLabel("Recorded download and upload bytes per second; missing samples are not inferred")
                }
            }
            Surface(title: "Highest CPU processes", subtitle: "CPU % IS A PROCESS-LIFETIME AVERAGE") {
                if let processes = model.system.processes {
                    ForEach(processes) { process in HStack { Text(process.name).font(.caption); Spacer(); Text(String(format: "%.1f%%", process.cpu)).font(.caption).monospacedDigit().frame(width: 65, alignment: .trailing); Text(bytes(process.residentBytes)).font(.caption).monospacedDigit().frame(width: 85, alignment: .trailing) } }
                } else { Text("Process information unavailable or awaiting the next visible refresh.").font(.caption).foregroundStyle(.secondary) }
                Text("Resident memory is shown. CPU is not an instantaneous sample and can exceed 100% for multicore processes. Process arguments are never collected.").font(.caption2).foregroundStyle(.secondary)
            }
            Text("Battery refreshes at most every 15s; storage every 60s. Sampling slows when views are hidden or Low Power Mode is enabled. Interface resets are skipped; virtual/VPN interfaces can still overlap traffic. GPU, temperature, battery health and discharge estimates are unavailable.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
