#if os(macOS)
import SwiftUI
import Charts
import MacPulseCore

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview = "Overview", screenTime = "Screen Time", codex = "Codex", applications = "Applications", system = "System", sessions = "Sessions", insights = "Insights", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .screenTime: return "hourglass"
        case .codex: return "terminal"
        case .applications: return "app.badge"
        case .system: return "cpu"
        case .sessions: return "clock.arrow.circlepath"
        case .insights: return "lightbulb"
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
        case .insights: return "A factual recap of your recorded time."
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
                    }.buttonStyle(.plain).accessibilityIdentifier("nav-" + item.rawValue).help(item.subtitle).padding(.horizontal, 10).padding(.bottom, 3)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 9) {
                    Label(preferences.demo ? "Demonstration mode" : "On this Mac", systemImage: preferences.demo ? "sparkles" : "lock.shield")
                        .font(.caption).foregroundStyle(preferences.demo ? PulseStyle.violet : PulseStyle.cyan)
                    Text(preferences.demo ? "Sample data. No live history is recorded." : "Private by design. No data leaves this Mac.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(18)
            }.navigationSplitViewColumnWidth(220)
        } detail: {
            if page == .settings {
                VStack(alignment: .leading, spacing: 0) { header.padding(30); SettingsView(model: model, preferences: preferences) }.background(Color(nsColor: .windowBackgroundColor))
            } else {
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
                    case .insights: InsightsPage(model: model)
                    case .settings: EmptyView()
                    }
                }.padding(30).frame(maxWidth: 1200)
            }.background(Color(nsColor: .windowBackgroundColor))
            }
        }.environment(\.pulseCompact, preferences.density == "Compact").environment(\.pulseReducedEffects, preferences.reducedEffects).tint(PulseStyle.accent(preferences.accent))
            .onAppear { page = DashboardPage(rawValue: preferences.defaultDashboard) ?? .overview; model.dashboardPage = page.rawValue }
            .onChange(of: page) { _, value in model.dashboardPage = value.rawValue }
            .preferredColorScheme(preferences.appearance == "System" ? nil : (preferences.appearance == "Light" ? .light : .dark))
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
                Text(model.system.deviceModel + " · " + model.sessionState).font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 5) { Circle().fill(preferences.demo ? PulseStyle.violet : PulseStyle.cyan).frame(width: 5, height: 5); Text(preferences.demo ? "Demo" : "Live system metrics").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.top, 6)
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
#endif
