#if os(macOS)
import SwiftUI
import Charts
import MacPulseCore

struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 26
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - radius), control: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath(); return path
    }
}
struct NotchView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var tab = "Overview"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group { if preferences.demo { Text("DEMO").font(.system(size: 8, weight: .bold)).foregroundStyle(PulseStyle.violet) } else { Image(systemName: "waveform.path.ecg").font(.system(size: 12)).foregroundStyle(PulseStyle.cyan) } }.frame(width: 40)
                Spacer(minLength: controller.notchWidth)
                compactIndicator.frame(width: 40)
            }.padding(.horizontal, 8).frame(height: controller.notchHeight)
                .contentShape(Rectangle()).onTapGesture { controller.click() }.accessibilityLabel("MacPulse notch. Click to expand or collapse.")
            if controller.state != .collapsed {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("MacPulse").font(.system(size: 13, weight: .semibold))
                        Text(preferences.demo ? "DEMO DATA" : "LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(preferences.demo ? PulseStyle.violet : PulseStyle.cyan).padding(.horizontal, 7).padding(.vertical, 4).background(.white.opacity(0.06), in: Capsule())
                        Spacer()
                        Button { controller.dashboard() } label: { Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Open dashboard").accessibilityLabel("Open MacPulse dashboard")
                        Button { controller.dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Collapse").accessibilityLabel("Collapse MacPulse notch")
                    }
                    if controller.state == .expanded {
                        Picker("Section", selection: $tab) { ForEach(["Overview", "Codex", "Activity"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden()
                    }
                    if tab == "Overview" || controller.state == .hover { overview }
                    else if tab == "Codex" { codex }
                    else { activity }
                    if controller.state == .hover {
                        Button("Expand control center") { controller.click() }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 18)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black, in: NotchShape()).clipShape(NotchShape())
            .foregroundStyle(.white).preferredColorScheme(.dark)
            .onAppear { tab = preferences.defaultNotch }
            .onChange(of: preferences.defaultNotch) { _, value in tab = value }
            .onHover { controller.hover($0) }
            .animation(reduceMotion || !preferences.animations ? nil : .spring(response: 0.32, dampingFraction: 0.88), value: controller.state)
    }
    private var overview: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ACTIVE TODAY").font(.system(size: 9, weight: .semibold)).foregroundStyle(.gray)
                    Text(Analytics.duration(model.todaySeconds)).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                    HStack(spacing: 5) { ApplicationIcon(bundle: preferences.demo ? "com.apple.dt.Xcode" : model.activeBundle).frame(width: 16, height: 16); Text(preferences.demo ? "Xcode" : model.activeApp) }.font(.caption).foregroundStyle(.gray).lineLimit(1)
                }
                Spacer()
                if preferences.showCPU { UsageRing(value: model.system.cpu ?? 0, label: model.system.cpu == nil ? "WAITING" : "CPU", available: model.system.cpu != nil) }
                UsageRing(value: model.system.memoryRatio, label: "MEMORY", tint: PulseStyle.violet, available: model.system.memoryAvailable)
            }
            if controller.state == .hover {
                HStack { Text("App " + Analytics.duration(model.currentAppSeconds)); Spacer(); Text("Session " + Analytics.duration(model.sessionSeconds)); Spacer(); Text("Battery " + percent(model.system.battery)) }.font(.caption2).foregroundStyle(.gray).monospacedDigit()
            }
            if controller.state == .expanded {
                Divider().overlay(.white.opacity(0.06))
                HStack {
                    mini("Session", Analytics.duration(model.sessionSeconds), "clock")
                    Spacer(); mini("Battery", percent(model.system.battery), "battery.75percent")
                    Spacer(); mini("Codex", "\(model.codex.count) sessions", "terminal")
                }
                if preferences.showMedia { HStack { Image(systemName: "music.note").foregroundStyle(.gray); Text("Now Playing unavailable").font(.caption); Spacer(); Text("No media provider connected").font(.caption2).foregroundStyle(.gray) }.padding(.vertical, 3) }
                Text(preferences.demo ? "Simulated statistics · switch to Live in Settings" : (preferences.monitoring ? "Recording foreground activity · stored on this Mac" : "Activity monitoring paused · enable in Settings"))
                    .font(.caption2).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func mini(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.gray); Text(value).font(.system(size: 14, weight: .medium)).monospacedDigit() }
    }
    private var compactIndicator: some View {
        Group {
            switch preferences.compactIndicator {
            case "CPU": Text(percent(model.system.cpu))
            case "Battery": Text(percent(model.system.battery))
            case "Session": Text(Analytics.duration(model.sessionSeconds))
            case "Codex": Text(model.usageSource == .live || model.usageSource == .demo ? (model.currentUsage?.windows.first.map { "\(Int($0.usedPercent))%" } ?? "—") : "—")
            default: Circle().fill(preferences.demo ? PulseStyle.violet : (model.sessionState == "Recording" || model.sessionState == "Idle" ? PulseStyle.cyan : .gray)).frame(width: 5, height: 5)
            }
        }.font(.system(size: 9, weight: .medium)).monospacedDigit().lineLimit(1).foregroundStyle(.gray)
            .accessibilityLabel(preferences.compactIndicator + " compact indicator" + (preferences.demo ? ", demonstration data" : ""))
    }
    private var codex: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let reading = model.currentUsage {
                HStack { Text(model.usageSource == .historical ? "Last reported usage" : "Reported usage").font(.headline); Spacer(); SourceBadge(source: model.usageSource) }
                ForEach(reading.windows.prefix(2)) { window in
                    HStack { Text(window.name).font(.caption).lineLimit(1); Spacer(); Text("\(Int(window.usedPercent))% used").font(.caption).monospacedDigit() }
                    ProgressView(value: window.usedPercent / 100).tint(PulseStyle.violet)
                    Text("Reset " + SampleMath.resetCountdown(reset: window.resetsAt, now: model.now)).font(.caption2).foregroundStyle(.gray).monospacedDigit()
                }
            } else { Text("Subscription usage unavailable").font(.headline) }
            HStack { mini("Local sessions", "\(model.codex.count)", "terminal"); Spacer(); mini("Projects", "\(Set(model.codex.map(\.project)).count)", "folder") }
            if let latest = model.codex.max(by: { $0.lastEvent < $1.lastEvent }) { HStack { Text(latest.project).font(.caption); Spacer(); Text(latest.lastEvent, style: .relative).font(.caption2).foregroundStyle(.gray) } }
            Text("Session tokens and plan allowance are separate measurements.").font(.caption2).foregroundStyle(.gray)
        }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.apps.isEmpty { EmptyState(title: "Your day starts here", detail: "Enable live monitoring in Settings.") }
            ForEach(model.apps.prefix(2)) { AppRow(app: $0, total: model.todaySeconds) }
            Divider()
            HStack { mini("Active today", Analytics.duration(model.todaySeconds), "hourglass"); Spacer(); mini("Session idle", Analytics.duration(model.sessionIdle), "pause") }
            let recent = model.records.filter { $0.start >= (preferences.demo ? model.today : model.sessionStart) }.suffix(12)
            if !recent.isEmpty {
                Chart(Array(recent)) { record in BarMark(xStart: .value("Start", record.start), xEnd: .value("End", record.end), y: .value("Category", record.category.rawValue)).foregroundStyle(PulseStyle.category(record.category)) }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 35).accessibilityLabel("Recent observed current-session application intervals")
            }
            Text(model.apps.first.map { "Top category: " + $0.category.rawValue } ?? "No recorded category activity").font(.caption2).foregroundStyle(.gray)
        }
    }
}
#endif
