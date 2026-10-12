#if os(macOS)
import SwiftUI
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
            HStack {
                Image(systemName: "waveform.path.ecg").font(.system(size: 12)).foregroundStyle(PulseStyle.cyan)
                Spacer(minLength: controller.notchWidth)
                Circle().fill(preferences.demo ? PulseStyle.violet : (preferences.monitoring ? PulseStyle.cyan : .gray)).frame(width: 5, height: 5)
            }.padding(.horizontal, 12).frame(height: controller.notchHeight)
                .contentShape(Rectangle()).onTapGesture { controller.click() }
            if controller.state != .collapsed {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("MacPulse").font(.system(size: 13, weight: .semibold))
                        Text(preferences.demo ? "DEMO DATA" : "LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(preferences.demo ? PulseStyle.violet : PulseStyle.cyan).padding(.horizontal, 7).padding(.vertical, 4).background(.white.opacity(0.06), in: Capsule())
                        Spacer()
                        Button { controller.dashboard() } label: { Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Open dashboard")
                        Button { controller.dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Collapse")
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
            .onHover { controller.hover($0) }
            .animation(reduceMotion || !preferences.animations ? nil : .spring(response: 0.32, dampingFraction: 0.88), value: controller.state)
    }
    private var overview: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ACTIVE TODAY").font(.system(size: 9, weight: .semibold)).foregroundStyle(.gray)
                    Text(Analytics.duration(model.todaySeconds)).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(preferences.demo ? "Xcode · MacPulse" : model.activeApp).font(.caption).foregroundStyle(.gray).lineLimit(1)
                }
                Spacer()
                if preferences.showCPU { UsageRing(value: model.system.cpu ?? 0, label: model.system.cpu == nil ? "WAITING" : "CPU", available: model.system.cpu != nil) }
                UsageRing(value: model.system.memoryRatio, label: "MEMORY", tint: PulseStyle.violet, available: model.system.memoryAvailable)
            }
            if controller.state == .expanded {
                Divider().overlay(.white.opacity(0.06))
                HStack {
                    mini("Session", Analytics.duration(model.sessionSeconds), "clock")
                    Spacer(); mini("Battery", percent(model.system.battery), "battery.75percent")
                    Spacer(); mini("Codex", "\(model.codex.count) sessions", "terminal")
                }
                Text(preferences.demo ? "Simulated statistics · switch to Live in Settings" : (preferences.monitoring ? "Recording foreground activity · stored on this Mac" : "Activity monitoring paused · enable in Settings"))
                    .font(.caption2).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func mini(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.gray); Text(value).font(.system(size: 14, weight: .medium)).monospacedDigit() }
    }
    private var codex: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscription usage unavailable").font(.headline)
            Text("Local session metadata is separate from subscription allowance.").font(.caption).foregroundStyle(.gray)
            HStack { mini("Sessions", "\(model.codex.count)", "terminal"); Spacer(); mini("Projects", "\(Set(model.codex.map(\.project)).count)", "folder") }
            ForEach(model.codex.prefix(2)) { session in HStack { Text(session.project).font(.caption); Spacer(); Text(session.date, style: .relative).font(.caption2).foregroundStyle(.gray) } }
        }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.apps.isEmpty { EmptyState(title: "Your day starts here", detail: "Enable live monitoring in Settings.") }
            ForEach(model.apps.prefix(3)) { AppRow(app: $0, total: model.todaySeconds) }
        }
    }
}
#endif
