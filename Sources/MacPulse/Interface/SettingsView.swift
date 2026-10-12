#if os(macOS)
import SwiftUI
import ServiceManagement
import UserNotifications
import MacPulseCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var deleteConfirmation = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var exportKind = ReportExportKind.activity
    var body: some View {
        Form {
            Section("General") {
                Toggle("Demonstration mode", isOn: $preferences.demo).toggleStyle(.checkbox).accessibilityIdentifier("setting-demo")
                Toggle("Record application activity", isOn: $preferences.monitoring).toggleStyle(.checkbox).accessibilityIdentifier("setting-recording").disabled(preferences.demo)
                Text(preferences.demo ? "All displayed statistics are demonstration data; activity recording is suspended." : model.sessionState + " · monitoring resumes with your saved preference at launch.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show menu bar icon", isOn: $preferences.menuBarVisible)
                Picker("Default dashboard page", selection: $preferences.defaultDashboard) { ForEach(DashboardPage.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        if SMAppService.mainApp.status == .requiresApproval { loginError = "Approve MacPulse in System Settings → General → Login Items." }
                    } catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
            }
            Section("Notch") {
                Toggle("Enable physical notch interface", isOn: $preferences.notchEnabled)
                Text("Turning this off keeps the menu bar control center and Dock dashboard available.").font(.caption).foregroundStyle(.secondary)
                Toggle("Expand on hover", isOn: $preferences.hover)
                HStack { Text("Hover delay"); Slider(value: $preferences.hoverDelay, in: 0.05...0.7, step: 0.05); Text("\(Int(preferences.hoverDelay * 1000)) ms").monospacedDigit().frame(width: 58) }
                Toggle("Animate transitions", isOn: $preferences.animations)
                Toggle("Show CPU ring", isOn: $preferences.showCPU)
                Picker("Collapsed indicator", selection: $preferences.compactIndicator) { ForEach(["Activity", "CPU", "Battery", "Session", "Codex"], id: \.self) { Text($0) } }
                Picker("Default notch tab", selection: $preferences.defaultNotch) { ForEach(["Overview", "Codex", "Activity"], id: \.self) { Text($0) } }
                Toggle("Show media integration status", isOn: $preferences.showMedia)
                Text("Now Playing is unavailable until a supported provider is connected. No private media API or fabricated track data is used.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Monitoring") {
                Picker("Idle threshold", selection: $preferences.idleThreshold) { Text("15 seconds").tag(15.0); Text("30 seconds").tag(30.0); Text("60 seconds").tag(60.0); Text("2 minutes").tag(120.0) }
                Picker("System sample interval", selection: $preferences.systemInterval) { Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0); Text("10 seconds").tag(10.0); Text("30 seconds").tag(30.0) }
                Text("Recording uses monotonic elapsed time. Idle after your threshold and observed sleep are excluded. Missed samples and clock changes are not backfilled. Hidden views and Low Power Mode slow system sampling.").font(.caption).foregroundStyle(.secondary)
                TextField("Excluded application bundle IDs", text: $preferences.exclusions).help("Comma-separated identifiers such as com.apple.Safari")
                Picker("Keep history", selection: $preferences.retention) { Text("30 days").tag(30); Text("90 days").tag(90); Text("365 days").tag(365) }
                Text("Shorter retention immediately removes older records. Application categories are editable on the Applications page.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Codex") {
                HStack { Text("Official CLI"); Spacer(); Text(preferences.usageExecutable.isEmpty ? "Not selected" : URL(fileURLWithPath: preferences.usageExecutable).lastPathComponent).foregroundStyle(.secondary); Button("Choose…") { model.chooseCodexExecutable() } }
                HStack { Text(model.usageStatus).font(.caption).foregroundStyle(.secondary); Spacer(); Button(model.refreshingUsage ? "Refreshing…" : "Read allowance") { model.refreshUsage() }.disabled(preferences.demo || preferences.usageExecutable.isEmpty || model.refreshingUsage) }
                Toggle("Refresh allowance every 5 minutes", isOn: $preferences.usageAutoRefresh).disabled(preferences.usageExecutable.isEmpty || preferences.demo)
                Text("Uses the documented Codex app-server protocol and the CLI's existing sign-in. No credentials are requested or copied. Older CLI versions, API-only accounts or unavailable service responses show an unavailable state.").font(.caption).foregroundStyle(.secondary)
                Toggle("Usage threshold notifications", isOn: $preferences.usageAlerts).disabled(model.usageSource != .live || preferences.demo)
                    .onChange(of: preferences.usageAlerts) { _, enabled in
                        guard enabled else { return }
                        Task {
                            do { let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]); if !granted { preferences.usageAlerts = false; model.note("Notifications were not permitted. Enable them in System Settings if desired.") } }
                            catch { preferences.usageAlerts = false; model.note(error.localizedDescription) }
                        }
                    }
                Picker("Usage alert threshold", selection: $preferences.alertThreshold) { Text("50%").tag(50); Text("80%").tag(80); Text("95%").tag(95) }.disabled(!preferences.usageAlerts)
                Text("Alerts require a fresh, authenticated allowance reading and a known reset window. Demo or stale data never triggers an alert. Notification permission is requested only when you enable this option.").font(.caption).foregroundStyle(.secondary)
                Button(model.importing ? "Importing…" : "Import local session metadata…") { model.importCodex() }.disabled(preferences.demo || model.importing)
                Text(model.importStatus).font(.caption).foregroundStyle(.secondary)
                TextField("Excluded project basenames", text: $preferences.projectExclusions)
                Text("Imports preserve earlier metadata and deduplicate session IDs. Messages, auth files and full project paths are not retained. Exclusions hide prior metadata from reports and prevent new imports; delete history to remove existing stored metadata.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Appearance", selection: $preferences.appearance) { ForEach(["Dark", "Light", "System"], id: \.self) { Text($0) } }
                Picker("Accent", selection: $preferences.accent) { ForEach(["Blue", "Violet", "Cyan"], id: \.self) { Text($0) } }
                Picker("Density", selection: $preferences.density) { Text("Comfortable").tag("Comfortable"); Text("Compact").tag("Compact") }
                Toggle("Reduce visual effects", isOn: $preferences.reducedEffects)
                Text("Notch surfaces remain black to blend with the display. System Reduce Motion is always respected.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy & export") {
                Text("Data stays in ~/Library/Application Support/MacPulse. No screenshots, keystrokes, window titles or browser history are collected. No Accessibility or Screen Recording permission is requested.").font(.caption).foregroundStyle(.secondary)
                Picker("Export", selection: $exportKind) { ForEach(ReportExportKind.allCases) { Text($0.rawValue).tag($0) } }
                Button("Export selected report…") { model.export(format: exportKind.rawValue) }
                Text("Full JSON includes retained application activity, sessions, idle/sleep intervals, system samples, Codex metadata and allowance readings. Demo exports are labeled and do not include live history.").font(.caption).foregroundStyle(.secondary)
                Button("Delete all live history…", role: .destructive) { deleteConfirmation = true }
            }
            Section("Diagnostics & source status") {
                LabeledContent("Activity data", value: model.source.rawValue + " · " + model.sessionState)
                LabeledContent("System metrics", value: preferences.demo ? "Demo" : "Live / estimated / unavailable by metric")
                LabeledContent("Subscription", value: model.usageSource.rawValue + " · " + model.usageStatus)
                LabeledContent("Database", value: model.databaseWarnings.isEmpty ? "Schema 2 · local SQLite" : "Some unreadable records are omitted; originals are preserved")
                ForEach(model.databaseWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                if model.diagnostics.isEmpty { Text("No recorded errors.").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { entry in Text(entry.element).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }.formStyle(.grouped)
            .confirmationDialog("Delete all live activity, sessions, system samples, imported metadata and recorded allowance readings? This cannot be undone.", isPresented: $deleteConfirmation) { Button("Delete all history", role: .destructive) { model.deleteData() }; Button("Cancel", role: .cancel) {} }
    }
}
#endif
