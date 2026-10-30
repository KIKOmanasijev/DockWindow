import AppKit
import SwiftUI
import DockWindowCore
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissions = PermissionsService()
    let tracker = WindowTracker()
    let thumbnails = ThumbnailService()
    let settings = AppSettings()
    lazy var actions = WindowActions(tracker: tracker)
    lazy var newWindowOpener = NewWindowOpener(tracker: tracker)
    lazy var switcher = SwitcherController(tracker: tracker, actions: actions, thumbnails: thumbnails, settings: settings, newWindowOpener: newWindowOpener)
    lazy var hotkey = HotkeyEventTap { [weak self] command in self?.switcher.handle(command) }
    var subscriptions = Set<AnyCancellable>()
    var permissionTimer: Timer?
    var statusItem: NSStatusItem?
    var onboarding: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockWindow")
        let menu = NSMenu()
        menu.addItem(withTitle: "Permissions...", action: #selector(showOnboarding), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Pause DockWindow", action: #selector(togglePause), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Debug: dump windows", action: #selector(dumpWindows), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DockWindow", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu; statusItem = item
        if !permissions.isGranted { showOnboarding() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePermissions() }
        }
        switcher.onSessionEnded = { [weak self] in self?.hotkey.endSession() }
        tracker.onWindowInventoryChanged = { [weak self] in self?.thumbnails.invalidateShareableContent() }
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updatePermissions() }.store(in: &subscriptions)
        updatePermissions()
        Log.system.info("DockWindow launched")
    }
    private func updatePermissions() {
        permissions.refresh()
        statusItem?.button?.toolTip = permissions.isGranted ? "DockWindow" : "DockWindow needs permissions"
        let enabled = permissions.isGranted && !settings.isPaused
        switcher.enabled = enabled
        var configuration = HotkeyConfiguration()
        configuration.enabled = enabled && settings.switcherEnabled
        configuration.shortcut = settings.switcherShortcut
        configuration.sameAppEnabled = settings.sameAppShortcutEnabled
        configuration.sameAppShortcut = settings.sameAppShortcut
        configuration.closeWithW = settings.switcherCloseWithW
        configuration.minimizeWithM = settings.switcherMinimizeWithM
        configuration.hideWithH = settings.switcherHideWithH
        configuration.quitWithQ = settings.switcherQuitWithQ
        hotkey.update(configuration: configuration)
        if enabled {
            tracker.start()
            if settings.switcherEnabled && !hotkey.start() { statusItem?.button?.toolTip = "Window switcher unavailable. Check Accessibility permission." }
        } else { hotkey.stop(); switcher.dismiss(); tracker.stop() }
        if !settings.switcherEnabled { hotkey.stop() }
    }
    @objc func togglePause() { settings.isPaused.toggle() }
    @objc func dumpWindows() { tracker.dumpWindows() }
    func applicationWillTerminate(_ notification: Notification) { permissionTimer?.invalidate(); hotkey.stop(); switcher.dismiss(); tracker.stop() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showOnboarding() {
        if onboarding == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Welcome to DockWindow"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PermissionsView(permissions: permissions)); window.center(); onboarding = window
        }
        onboarding?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showOnboarding(); return true }
}
struct PermissionsView: View {
    @ObservedObject var permissions: PermissionsService
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your windows, on this desktop").font(.title2.bold())
            Text("DockWindow needs both permissions before it can replace the Dock or window switcher.").foregroundStyle(.secondary)
            HStack { Label(permissions.accessibility ? "Accessibility granted" : "Accessibility missing", systemImage: permissions.accessibility ? "checkmark.circle.fill" : "exclamationmark.triangle"); Spacer(); Button("Open System Settings", action: permissions.openAccessibility) }
            HStack { Label(permissions.screenRecording ? "Screen Recording granted" : "Screen Recording missing", systemImage: permissions.screenRecording ? "checkmark.circle.fill" : "exclamationmark.triangle"); Spacer(); Button("Open System Settings", action: permissions.openScreenRecording) }
            Text("Screen Recording may require a relaunch. The replacement Dock hides the native Dock while enabled and restores it when paused or closed.").font(.caption).foregroundStyle(.secondary)
            Button("Relaunch DockWindow") {
                let url = Bundle.main.bundleURL
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
                NSApp.terminate(nil)
            }
        }.padding(28).onReceive(timer) { _ in permissions.refresh() }
    }
}
