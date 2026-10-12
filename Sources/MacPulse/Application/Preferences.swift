#if os(macOS)
import SwiftUI
import MacPulseCore

final class Preferences: ObservableObject {
    @Published var demo: Bool { didSet { defaults.set(demo, forKey: "demo") } }
    @Published var monitoring: Bool { didSet { defaults.set(monitoring, forKey: "monitoring") } }
    @Published var hover: Bool { didSet { defaults.set(hover, forKey: "hover") } }
    @Published var animations: Bool { didSet { defaults.set(animations, forKey: "animations") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var retention: Int { didSet { defaults.set(retention, forKey: "retention") } }
    @Published var exclusions: String { didSet { defaults.set(exclusions, forKey: "exclusions") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    @Published var categories: [String: String] { didSet { defaults.set(categories, forKey: "categories") } }
    @Published var showCPU: Bool { didSet { defaults.set(showCPU, forKey: "showCPU") } }
    @Published var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: "notchEnabled") } }
    @Published var menuBarVisible: Bool { didSet { defaults.set(menuBarVisible, forKey: "menuBarVisible") } }
    @Published var defaultDashboard: String { didSet { defaults.set(defaultDashboard, forKey: "defaultDashboard") } }
    @Published var defaultNotch: String { didSet { defaults.set(defaultNotch, forKey: "defaultNotch") } }
    @Published var compactIndicator: String { didSet { defaults.set(compactIndicator, forKey: "compactIndicator") } }
    @Published var showMedia: Bool { didSet { defaults.set(showMedia, forKey: "showMedia") } }
    @Published var idleThreshold: Double { didSet { defaults.set(idleThreshold, forKey: "idleThreshold") } }
    @Published var systemInterval: Double { didSet { defaults.set(systemInterval, forKey: "systemInterval") } }
    @Published var usageExecutable: String { didSet { defaults.set(usageExecutable, forKey: "usageExecutable") } }
    @Published var usageAutoRefresh: Bool { didSet { defaults.set(usageAutoRefresh, forKey: "usageAutoRefresh") } }
    @Published var usageAlerts: Bool { didSet { defaults.set(usageAlerts, forKey: "usageAlerts") } }
    @Published var alertThreshold: Int { didSet { defaults.set(alertThreshold, forKey: "alertThreshold") } }
    @Published var projectExclusions: String { didSet { defaults.set(projectExclusions, forKey: "projectExclusions") } }
    @Published var density: String { didSet { defaults.set(density, forKey: "density") } }
    @Published var accent: String { didSet { defaults.set(accent, forKey: "accent") } }
    @Published var reducedEffects: Bool { didSet { defaults.set(reducedEffects, forKey: "reducedEffects") } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        SettingsSchema.register(in: defaults)
        demo = defaults.bool(forKey: "demo"); monitoring = defaults.bool(forKey: "monitoring")
        hover = defaults.bool(forKey: "hover"); animations = defaults.bool(forKey: "animations")
        hoverDelay = SettingsSchema.clamped(defaults.double(forKey: "hoverDelay"), range: 0.05...0.7, fallback: 0.15); retention = defaults.integer(forKey: "retention")
        exclusions = defaults.string(forKey: "exclusions") ?? ""; appearance = defaults.string(forKey: "appearance") ?? "Dark"
        categories = defaults.dictionary(forKey: "categories") as? [String: String] ?? [:]; showCPU = defaults.bool(forKey: "showCPU")
        notchEnabled = defaults.bool(forKey: "notchEnabled")
        menuBarVisible = defaults.bool(forKey: "menuBarVisible")
        defaultDashboard = defaults.string(forKey: "defaultDashboard") ?? "Overview"
        defaultNotch = defaults.string(forKey: "defaultNotch") ?? "Overview"
        compactIndicator = defaults.string(forKey: "compactIndicator") ?? "Activity"
        showMedia = defaults.bool(forKey: "showMedia")
        idleThreshold = SettingsSchema.clamped(defaults.double(forKey: "idleThreshold"), range: 15...120, fallback: 60)
        systemInterval = SettingsSchema.clamped(defaults.double(forKey: "systemInterval"), range: 2...30, fallback: 5)
        usageExecutable = defaults.string(forKey: "usageExecutable") ?? ""
        usageAutoRefresh = defaults.bool(forKey: "usageAutoRefresh")
        usageAlerts = defaults.bool(forKey: "usageAlerts")
        alertThreshold = defaults.integer(forKey: "alertThreshold")
        projectExclusions = defaults.string(forKey: "projectExclusions") ?? ""
        density = defaults.string(forKey: "density") ?? "Comfortable"
        accent = defaults.string(forKey: "accent") ?? "Blue"
        reducedEffects = defaults.bool(forKey: "reducedEffects")
    }
    var storage: UserDefaults { defaults }
    func category(for bundle: String) -> ActivityCategory {
        categories[bundle].flatMap(ActivityCategory.init(rawValue:)) ?? .suggested(for: bundle)
    }
    func isProjectExcluded(_ project: String) -> Bool { projectExclusions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.contains(project) }
    func isExcluded(_ bundle: String) -> Bool {
        exclusions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.contains(bundle)
    }
}
#endif
