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
    private let defaults = UserDefaults.standard
    init() {
        defaults.register(defaults: ["demo": true, "monitoring": false, "hover": true, "animations": true, "hoverDelay": 0.15, "retention": 90, "exclusions": "", "appearance": "Dark", "showCPU": true])
        demo = defaults.bool(forKey: "demo"); monitoring = defaults.bool(forKey: "monitoring")
        hover = defaults.bool(forKey: "hover"); animations = defaults.bool(forKey: "animations")
        hoverDelay = defaults.double(forKey: "hoverDelay"); retention = defaults.integer(forKey: "retention")
        exclusions = defaults.string(forKey: "exclusions") ?? ""; appearance = defaults.string(forKey: "appearance") ?? "Dark"
        categories = defaults.dictionary(forKey: "categories") as? [String: String] ?? [:]; showCPU = defaults.bool(forKey: "showCPU")
    }
    func category(for bundle: String) -> ActivityCategory {
        categories[bundle].flatMap(ActivityCategory.init(rawValue:)) ?? .suggested(for: bundle)
    }
    func isExcluded(_ bundle: String) -> Bool {
        exclusions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.contains(bundle)
    }
}
#endif
