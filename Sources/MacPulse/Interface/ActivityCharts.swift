#if os(macOS)
import SwiftUI
import Charts
import MacPulseCore

struct StackedActivityChart: View {
    let records: [ActivityRecord]
    let sessions: [ComputerSession]
    let ending: Date
    var days = 7
    @State private var inspection: Date?
    var body: some View {
        let values = HistoryAnalytics.stacked(records: records, ending: ending, count: days)
        let coverage = HistoryAnalytics.daily(records: records, sessions: sessions, ending: ending, count: days)
        VStack(alignment: .leading, spacing: 10) {
            if values.isEmpty { EmptyState(title: "No recorded activity in this range", detail: "Dates without observations are unknown, not zero usage.") }
            else {
                Chart(values) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Active hours", day.seconds / 3600))
                        .foregroundStyle(by: .value("Category", day.category.rawValue)).cornerRadius(3)
                }.chartForegroundStyleScale(domain: ActivityCategory.allCases.map(\.rawValue), range: ActivityCategory.allCases.map(PulseStyle.category))
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: days > 7 ? 5 : 1)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                    .chartYScale(domain: 0...max(1, coverage.compactMap(\.seconds).max().map { $0 / 3600 * 1.1 } ?? 1))
                    .chartXSelection(value: $inspection).frame(height: 205)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                                switch phase {
                                case .active(let location): if let frame = proxy.plotFrame { inspection = proxy.value(atX: location.x - geometry[frame].minX, as: Date.self) }
                                case .ended: inspection = nil
                                }
                            }
                        }
                    }
            }
            if let inspection, let day = coverage.first(where: { Calendar.current.isDate($0.date, inSameDayAs: inspection) }) {
                Text(day.date.formatted(date: .abbreviated, time: .omitted) + " · " + (day.seconds.map(Analytics.duration) ?? "No observations")).font(.caption).monospacedDigit()
            }
            Text("\(coverage.filter { $0.seconds != nil }.count) of \(days) days contain observations. Bars show recorded time only; blank dates may be unobserved.").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityLabel("Recorded active hours by day and activity category. Unobserved days have no bar.")
    }
}
struct DayTimeline: View {
    let records: [ActivityRecord]
    let intervals: [StateInterval]
    let date: Date
    @State private var selectedTime: Date?
    @State private var hovered: Date?
    @State private var hours = 24
    @State private var detail: ActivityRecord?
    private var start: Date { Calendar.current.startOfDay(for: date) }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: start)! }
    private var active: [ActivityRecord] { records.filter { $0.overlap(from: start, to: end) > 0 } }
    private var other: [StateInterval] { intervals.filter { $0.end > start && $0.start < end } }
    private var inspected: ActivityRecord? { (selectedTime ?? hovered).flatMap { time in active.first { $0.start <= time && $0.end >= time } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Recorded intervals").font(.caption).foregroundStyle(.secondary); Spacer(); Picker("Timeline zoom", selection: $hours) { Text("Full day").tag(24); Text("6 hours").tag(6) }.pickerStyle(.segmented).frame(width: 200) }
            if active.isEmpty && other.isEmpty { EmptyState(title: "No intervals on this date", detail: "Choose another date or enable live activity recording.") }
            else {
                Chart {
                    ForEach(active) { record in
                        BarMark(xStart: .value("Start", max(start, record.start)), xEnd: .value("End", min(end, record.end)), y: .value("State", "Active"))
                            .foregroundStyle(PulseStyle.category(record.category)).cornerRadius(2)
                    }
                    ForEach(other) { interval in
                        BarMark(xStart: .value("Start", max(start, interval.start)), xEnd: .value("End", min(end, interval.end)), y: .value("State", interval.kind.rawValue))
                            .foregroundStyle(interval.kind == .sleep ? Color.indigo.opacity(0.6) : Color.gray.opacity(0.5)).cornerRadius(2)
                    }
                }.chartXScale(domain: start...end).chartScrollableAxes(.horizontal).chartXVisibleDomain(length: Double(hours) * 3600)
                    .chartXAxis { AxisMarks(values: .stride(by: .hour, count: hours == 24 ? 3 : 1)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
                    .chartXSelection(value: $selectedTime).frame(height: other.isEmpty ? 100 : 145)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                                switch phase {
                                case .active(let location): if let frame = proxy.plotFrame { hovered = proxy.value(atX: location.x - geometry[frame].minX, as: Date.self) }
                                case .ended: hovered = nil
                                }
                            }.onTapGesture { if let inspected { detail = inspected } }
                        }
                    }
                if let inspected {
                    HStack {
                        Label(inspected.appName, systemImage: "app").font(.caption)
                        Text(inspected.start.formatted(date: .omitted, time: .shortened) + " – " + inspected.end.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Spacer(); Text(Analytics.duration(inspected.duration)).font(.caption).monospacedDigit()
                        Button("Details") { detail = inspected }.controlSize(.small)
                    }
                }
                Text("Hover or select an active segment for details. Blank space is unobserved, not inferred idle time.").font(.caption2).foregroundStyle(.secondary)
            }
        }.accessibilityLabel("Application, idle and sleep intervals for the selected local calendar day")
            .sheet(item: $detail) { record in
                VStack(alignment: .leading, spacing: 18) {
                    HStack { ApplicationIcon(bundle: record.bundleID); Text(record.appName).font(.title2.weight(.semibold)); Spacer(); Button("Done") { detail = nil } }
                    LabeledContent("Category", value: record.category.rawValue)
                    LabeledContent("Start", value: record.start.formatted())
                    LabeledContent("End", value: record.end.formatted())
                    LabeledContent("Active duration", value: Analytics.duration(record.duration))
                    Text(record.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(28).frame(width: 500)
            }
    }
}
struct SessionSummaryRow: View {
    let session: ComputerSession
    let records: [ActivityRecord]
    var body: some View {
        let end = session.end ?? session.observedUntil
        let app = Analytics.applications(records, from: session.start, to: end).first
        HStack(spacing: 14) {
            Image(systemName: session.end == nil ? "record.circle" : "clock").foregroundStyle(session.end == nil ? PulseStyle.cyan : PulseStyle.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.start, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 13, weight: .medium))
                Text(app.map { "Most used: " + $0.name } ?? "No foreground activity").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Analytics.duration(session.activeSeconds) + " active · " + Analytics.duration(session.idleSeconds) + " idle").font(.caption).monospacedDigit()
                Text(session.end.map { "Ended " + $0.formatted(date: .omitted, time: .shortened) } ?? "In progress").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}
#endif
