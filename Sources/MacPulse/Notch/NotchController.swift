#if os(macOS)
import AppKit
import SwiftUI
import Combine
import MacPulseCore

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class NotchController: ObservableObject {
    @Published private(set) var interaction = NotchInteraction()
    @Published private(set) var notchWidth: CGFloat = 180
    @Published private(set) var notchHeight: CGFloat = 32
    private let model: AppModel
    private let openDashboard: () -> Void
    private let panel: NotchPanel
    private var screen: NSScreen?
    private var fallbackAnchor: NSRect?
    private var displayObserver: NSObjectProtocol?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var subscriptions: Set<AnyCancellable> = []
    private var wakeObserver: NSObjectProtocol?
    private var hoverTask: Task<Void, Never>?
    var state: NotchState { interaction.state }
    var size: CGSize {
        switch state {
        case .collapsed: return CGSize(width: notchWidth + 96, height: notchHeight)
        case .hover: return CGSize(width: 480, height: notchHeight + 210)
        case .expanded: return CGSize(width: 580, height: notchHeight + 400)
        }
    }
    init(model: AppModel, openDashboard: @escaping () -> Void) {
        self.model = model; self.openDashboard = openDashboard
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: NotchView(controller: self, model: model, preferences: model.preferences))
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.reposition() } }
        model.preferences.$notchEnabled.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.reposition() } }.store(in: &subscriptions)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.reposition() } }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in Task { @MainActor in self?.dismissIfOutside() } }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 { Task { @MainActor in self?.dismiss() } }
            else if event.type != .keyDown { Task { @MainActor in self?.dismissIfOutside() } }
            return event
        }
    }
    deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        hoverTask?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
    func reposition() {
        guard model.preferences.notchEnabled else { interaction.dismiss(); panel.orderOut(nil); screen = nil; model.notchExpanded = false; return }
        // Choose the built-in notched display wherever it appears in the display layout.
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        if let screen {
            notchHeight = screen.safeAreaInsets.top
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea { notchWidth = max(100, right.minX - left.maxX) }
            updateFrame(animated: false); panel.orderFrontRegardless()
        } else if state == .collapsed { panel.orderOut(nil) }
        else { updateFrame(animated: false) }
    }
    func hover(_ inside: Bool) {
        hoverTask?.cancel()
        if inside {
            let delay = model.preferences.hoverDelay
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.interaction.enter(hoverEnabled: self.model.preferences.hover)
                self.updateFrame()
            }
        } else {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                self.interaction.leave(); self.updateFrame()
            }
        }
    }
    func click() { hoverTask?.cancel(); interaction.click(); updateFrame() }
    func dismiss() {
        hoverTask?.cancel(); interaction.dismiss()
        if (screen?.safeAreaInsets.top ?? 0) == 0 || !model.preferences.notchEnabled { panel.orderOut(nil); screen = nil; model.notchExpanded = false } else { updateFrame() }
    }
    func dashboard() { dismiss(); openDashboard() }
    func toggleFromMenuBar(anchor: NSRect? = nil) {
        fallbackAnchor = anchor
        if !model.preferences.notchEnabled { screen = nil }
        if screen == nil { screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main; notchHeight = 12; notchWidth = 160 }
        click(); panel.orderFrontRegardless()
        // A non-notch monitor uses a conventional menu-bar popover position below the bar.
        if screen?.safeAreaInsets.top == 0 && state == .collapsed { panel.orderOut(nil); screen = nil }
    }
    private func dismissIfOutside() { if !panel.frame.contains(NSEvent.mouseLocation) { dismiss() } }
    private func updateFrame(animated: Bool = true) {
        guard let screen else { return }
        let physicalNotch = model.preferences.notchEnabled && screen.safeAreaInsets.top > 0
        let top = physicalNotch ? screen.frame.maxY : screen.visibleFrame.maxY
        let desiredX = (physicalNotch ? screen.frame.midX : (fallbackAnchor?.midX ?? screen.frame.midX)) - size.width / 2
        let x = min(screen.frame.maxX - size.width - 8, max(screen.frame.minX + 8, desiredX))
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        model.notchExpanded = state != .collapsed
        let animate = animated && model.preferences.animations && !model.preferences.reducedEffects && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(frame, display: true, animate: animate)
    }
}
#endif
