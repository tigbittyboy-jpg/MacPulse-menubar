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
    static func accent(_ name: String) -> Color { name == "Violet" ? violet : (name == "Cyan" ? cyan : blue) }
    static func category(_ value: ActivityCategory) -> Color {
        switch value { case .development: return blue; case .music: return violet; case .gaming: return .pink; case .browsing: return cyan; case .communication: return .green; case .entertainment: return .orange; case .utilities: return .gray; case .other: return .secondary }
    }
    static let surface = Color.primary.opacity(0.045)
}
private struct CompactDensityKey: EnvironmentKey { static let defaultValue = false }
private struct ReducedEffectsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var pulseCompact: Bool { get { self[CompactDensityKey.self] } set { self[CompactDensityKey.self] = newValue } }
    var pulseReducedEffects: Bool { get { self[ReducedEffectsKey.self] } set { self[ReducedEffectsKey.self] = newValue } }
}
struct SourceBadge: View {
    let source: DataSourceState
    var body: some View {
        Text(source.rawValue.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.5)
            .foregroundStyle(source == .demo ? PulseStyle.violet : (source == .live ? PulseStyle.cyan : Color.secondary))
            .padding(.horizontal, 7).padding(.vertical, 4).background(Color.primary.opacity(0.06), in: Capsule())
            .accessibilityLabel("Data source: " + source.rawValue)
    }
}
struct Surface<Content: View>: View {
    @Environment(\.pulseCompact) private var compact
    @Environment(\.pulseReducedEffects) private var reducedEffects
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(subtitle) }
            }
            content()
        }.padding(compact ? 15 : 20).frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(reducedEffects ? 0 : 0.06)))
    }
}
enum MetricCardSize: Equatable { case compact, standard, expanded }
struct MetricCard: View {
    @Environment(\.pulseCompact) private var compact
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var tint = PulseStyle.blue
    var source: DataSourceState = .historical
    var context: String? = nil
    var trend: String? = nil
    var samples: [Double] = []
    var size: MetricCardSize = .standard
    var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Image(systemName: symbol).foregroundStyle(tint); Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); if loading { ProgressView().controlSize(.mini) } else { SourceBadge(source: source) } }
            Text(source == .unavailable || source == .permissionRequired ? "—" : value).font(.system(size: compact || size == .compact ? 24 : 29, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            if let context { Text(context).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            if let trend { Label(trend, systemImage: "chart.line.uptrend.xyaxis").font(.caption2).foregroundStyle(tint) }
            if !samples.isEmpty {
                Chart(Array(samples.enumerated()), id: \.offset) { entry in LineMark(x: .value("Sample", entry.offset), y: .value("Value", entry.element)).foregroundStyle(tint) }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 30).accessibilityLabel(title + " recent samples")
            }
        }.padding(compact ? 15 : 20).frame(maxWidth: .infinity, minHeight: compact || size == .compact ? 108 : 126, alignment: .leading)
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
@MainActor private enum ApplicationIconCache {
    static var values: [String: NSImage] = [:]
    static func image(_ bundle: String) -> NSImage? {
        if let image = values[bundle] { return image }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        if values.count > 200 { values.removeAll() }
        let image = NSWorkspace.shared.icon(forFile: url.path); values[bundle] = image; return image
    }
}
struct ApplicationIcon: View {
    let bundle: String
    var body: some View {
        Group {
            if let image = ApplicationIconCache.image(bundle) { Image(nsImage: image).resizable() }
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
                HStack { Text(app.name).font(.system(size: 13, weight: .medium)); Spacer(); Text(Analytics.duration(app.seconds) + " · " + "\(Int(app.seconds / max(1, total) * 100))%").font(.system(size: 12, weight: .medium)).monospacedDigit() }
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
    var gapTolerance: Double = 20
    @State private var inspected: Date?
    private var segments: [(point: PerformancePoint, group: Int)] {
        var group = 0
        let sorted = points.sorted { $0.date < $1.date }
        return sorted.enumerated().map { index, point in
            if index > 0 && point.date.timeIntervalSince(sorted[index - 1].date) > gapTolerance { group += 1 }
            return (point, group)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if points.isEmpty { EmptyState(title: "No performance samples", detail: "Live samples appear after two successful readings. Historical gaps remain empty.") }
            else {
                Chart(segments, id: \.point.id) { entry in
                    LineMark(x: .value("Time", entry.point.date), y: .value("Utilization %", entry.point.cpu * 100), series: .value("Metric", "CPU-\(entry.group)")).foregroundStyle(PulseStyle.blue)
                    LineMark(x: .value("Time", entry.point.date), y: .value("Utilization %", entry.point.memory * 100), series: .value("Metric", "Memory-\(entry.group)")).foregroundStyle(PulseStyle.violet)
                }.chartYScale(domain: 0...100).chartLegend(.hidden).chartXSelection(value: $inspected).frame(height: 150)
                if let inspected, let sample = points.min(by: { abs($0.date.timeIntervalSince(inspected)) < abs($1.date.timeIntervalSince(inspected)) }) {
                    Text("\(sample.date.formatted(date: .omitted, time: .standard)) · CPU \(Int(sample.cpu * 100))% · Memory \(Int(sample.memory * 100))%").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }.accessibilityLabel("CPU and memory percentage over recorded sample times. Gaps are not interpolated.")
    }
}
struct EmptyState: View {
    let title: String
    let detail: String
    var body: some View { VStack(spacing: 10) { Image(systemName: "waveform.path").font(.largeTitle).foregroundStyle(.tertiary); Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(28) }
}
func percent(_ number: Double?) -> String { guard let number, number.isFinite else { return "—" }; return "\(Int(min(1, max(0, number)) * 100))%" }
func bytes(_ number: Double) -> String { guard number.isFinite else { return "—" }; return ByteCountFormatter.string(fromByteCount: Int64(min(9e18, max(0, number))), countStyle: .decimal) }
#endif
