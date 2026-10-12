import Foundation

public enum SettingsSchema {
    public static func register(in defaults: UserDefaults) {
        defaults.register(defaults: [
            "demo": true, "monitoring": false, "hover": true, "animations": true,
            "hoverDelay": 0.15, "retention": 90, "exclusions": "", "appearance": "Dark", "showCPU": true,
            "notchEnabled": true, "menuBarVisible": true, "defaultDashboard": "Overview", "defaultNotch": "Overview",
            "compactIndicator": "Activity", "showMedia": true, "idleThreshold": 60.0, "systemInterval": 5.0,
            "usageExecutable": "", "usageAutoRefresh": false, "usageAlerts": false, "alertThreshold": 80,
            "projectExclusions": "", "density": "Comfortable", "accent": "Blue", "reducedEffects": false
        ])
    }
    public static func clamped(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}
