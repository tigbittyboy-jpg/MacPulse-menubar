#if os(macOS)
import SwiftUI
import AppKit

@main struct MacPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { SettingsView(model: delegate.model, preferences: delegate.model.preferences).frame(width: 570, height: 650) } }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var status: NSStatusItem?
    private var notch: NotchController?
    private var dashboard: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let applicationMenu = NSMenuItem(); menu.addItem(applicationMenu)
        let items = NSMenu(); applicationMenu.submenu = items
        items.addItem(withTitle: "About MacPulse", action: #selector(showAbout), keyEquivalent: "")
        items.addItem(.separator())
        items.addItem(withTitle: "Quit MacPulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status?.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "MacPulse")
        status?.button?.target = self; status?.button?.action = #selector(togglePanel)
        notch = NotchController(model: model, openDashboard: { [weak self] in self?.showDashboard() })
        notch?.reposition()
        showDashboard()
    }
    @objc private func togglePanel() {
        let anchor: NSRect?
        if let button = status?.button, let window = button.window { anchor = window.convertToScreen(button.convert(button.bounds, to: nil)) } else { anchor = nil }
        notch?.toggleFromMenuBar(anchor: anchor)
    }
    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "MacPulse", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "Local activity. A quieter view of your Mac.")]) }
    func showDashboard() {
        if dashboard == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "MacPulse"; window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 920, height: 660); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DashboardView(model: model, preferences: model.preferences))
            window.center(); dashboard = window
        }
        NSApp.activate(ignoringOtherApps: true); dashboard?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDashboard(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.endSession() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#else
import Foundation
@main enum UnsupportedPlatform {
    static func main() { print("MacPulse requires macOS 14 or later. Portable data-layer tests: swift test") }
}
#endif
