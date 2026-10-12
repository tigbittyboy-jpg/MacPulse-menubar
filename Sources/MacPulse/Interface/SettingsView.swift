#if os(macOS)
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var deleteConfirmation = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var body: some View {
        Form {
            Section("Mode & monitoring") {
                Toggle("Demonstration mode", isOn: $preferences.demo)
                Text(preferences.demo ? "All displayed statistics are sample data. Live activity recording is suspended." : "System metrics are live. Enable monitoring to record foreground application time.").font(.caption).foregroundStyle(.secondary)
                Toggle("Record application activity", isOn: $preferences.monitoring).disabled(preferences.demo)
                Text("Tracks application identity and duration only. No screenshots, keystrokes, window titles or browsing history. Idle periods longer than 60 seconds and sleep are excluded. No Accessibility or Screen Recording permission is required.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Notch & appearance") {
                Toggle("Expand on hover", isOn: $preferences.hover)
                HStack { Text("Hover delay"); Slider(value: $preferences.hoverDelay, in: 0.05...0.7, step: 0.05); Text("\(Int(preferences.hoverDelay * 1000)) ms").monospacedDigit().frame(width: 58) }
                Toggle("Animate transitions", isOn: $preferences.animations)
                Toggle("Show CPU ring in notch", isOn: $preferences.showCPU)
                Picker("Dashboard appearance", selection: $preferences.appearance) { ForEach(["Dark", "Light", "System"], id: \.self) { Text($0) } }
                Text("The notch remains dark to blend with the display. System Reduce Motion is always respected.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        if SMAppService.mainApp.status == .requiresApproval { loginError = "Approve MacPulse in System Settings → General → Login Items." }
                    } catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                Text("Requires an installed app bundle. Closing the dashboard keeps the menu bar and notch available.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy & data") {
                TextField("Excluded bundle IDs (comma separated)", text: $preferences.exclusions)
                Picker("Keep history", selection: $preferences.retention) { Text("30 days").tag(30); Text("90 days").tag(90); Text("365 days").tag(365) }
                Text("Changing retention removes older records immediately. Categories can be changed on the Applications page.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Export CSV…") { model.exportCSV() }; Spacer(); Button("Delete all live history…", role: .destructive) { deleteConfirmation = true } }
                Text("History is stored in ~/Library/Application Support/MacPulse. Preferences are stored locally in UserDefaults. Demo exports are named separately.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Codex integration") {
                Button(model.importing ? "Importing…" : "Import local session metadata…") { model.importCodex() }.disabled(preferences.demo || model.importing)
                Text("Select the sessions directory yourself. Only project basenames, timestamps and aggregate token counts are saved. No auth files or session contents are retained or transmitted. Subscription reset timers and threshold notifications are unavailable until a reliable source is integrated.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
            .confirmationDialog("Delete all recorded activity and imported Codex metadata? This cannot be undone.", isPresented: $deleteConfirmation) { Button("Delete all history", role: .destructive) { model.deleteData() }; Button("Cancel", role: .cancel) {} }
    }
}
#endif
