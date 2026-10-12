#if os(macOS)
import SwiftUI
import Charts
import AppKit
import MacPulseCore

enum PulseStyle {
    static let blue = Color(red: 0.32, green: 0.59, blue: 1)
    static let violet = Color(red: 0.65, green: 0.51, blue: 1)
    static let cyan = Color(red: 0.28, green: 0.83, blue: 0.86)
    static let background = Color(red: 0.065, green: 0.07, blue: 0.09)
    static let surface = Color.primary.opacity(0.045)
}
struct Surface<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.06)))
    }
}
struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var tint = PulseStyle.blue
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Image(systemName: symbol).foregroundStyle(tint); Spacer(); Text(title).font(.caption).foregroundStyle(.secondary) }
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(20).frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .background(PulseStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.06)))
    }
}
struct UsageRing: View {
    let value: Double
    let label: String
    var tint = PulseStyle.blue
    var available = true
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
            Circle().trim(from: 0, to: min(1, max(0, value))).stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 3) { Text(available ? "\(Int(value * 100))%" : "—").font(.system(size: 17, weight: .semibold)).monospacedDigit(); Text(label).font(.system(size: 9)).foregroundStyle(.secondary) }
        }.frame(width: 66, height: 66)
    }
}
struct ApplicationIcon: View {
    let bundle: String
    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable() }
            else { Image(systemName: "app.fill").resizable().foregroundStyle(PulseStyle.violet).padding(5) }
        }.frame(width: 32, height: 32)
    }
}
struct AppRow: View {
    let app: AppUsage
    let total: Double
    var body: some View {
        HStack(spacing: 12) {
            ApplicationIcon(bundle: app.bundleID)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(app.name).font(.system(size: 13, weight: .medium)); Spacer(); Text(Analytics.duration(app.seconds)).font(.system(size: 12, weight: .medium)).monospacedDigit() }
                GeometryReader { geometry in
                    Capsule().fill(Color.primary.opacity(0.07)).overlay(alignment: .leading) { Capsule().fill(PulseStyle.blue.gradient).frame(width: geometry.size.width * min(1, app.seconds / max(1, total))) }
                }.frame(height: 4)
            }
        }.padding(.vertical, 5)
    }
}
struct WeeklyChart: View {
    let days: [DailyUsage]
    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", day.seconds / 3600))
                .foregroundStyle(PulseStyle.blue.gradient).cornerRadius(5)
        }.chartXAxis { AxisMarks(values: .stride(by: .day, count: days.count > 7 ? 7 : 1)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)); AxisTick() } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Color.primary.opacity(0.06)); AxisValueLabel() } }
            .frame(height: 180)
            .accessibilityLabel("Active hours by day")
    }
}
struct PerformanceChart: View {
    let points: [PerformancePoint]
    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Time", point.date), y: .value("Utilization", point.cpu * 100), series: .value("Metric", "CPU"))
                .foregroundStyle(PulseStyle.blue).interpolationMethod(.catmullRom)
            LineMark(x: .value("Time", point.date), y: .value("Utilization", point.memory * 100), series: .value("Metric", "Memory"))
                .foregroundStyle(PulseStyle.violet).interpolationMethod(.catmullRom)
        }.chartYScale(domain: 0...100).chartXAxis(.hidden).frame(height: 155)
    }
}
struct EmptyState: View {
    let title: String
    let detail: String
    var body: some View { VStack(spacing: 10) { Image(systemName: "waveform.path").font(.largeTitle).foregroundStyle(.tertiary); Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(28) }
}
func percent(_ number: Double?) -> String { number.map { "\(Int($0 * 100))%" } ?? "—" }
func bytes(_ number: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0, number)), countStyle: .decimal) }
#endif
