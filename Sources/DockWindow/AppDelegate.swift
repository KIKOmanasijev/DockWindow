import AppKit
import SwiftUI
import DockWindowCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissions = PermissionsService()
    let tracker = WindowTracker()
    let thumbnails = ThumbnailService()
    var permissionTimer: Timer?
    var statusItem: NSStatusItem?
    var onboarding: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockWindow")
        let menu = NSMenu()
        menu.addItem(withTitle: "Permissions...", action: #selector(showOnboarding), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Debug: dump windows", action: #selector(dumpWindows), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DockWindow", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu; statusItem = item
        if !permissions.isGranted { showOnboarding() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePermissions() }
        }
        tracker.onWindowInventoryChanged = { [weak self] in self?.thumbnails.invalidateShareableContent() }
        updatePermissions()
        Log.system.info("DockWindow launched")
    }
    private func updatePermissions() {
        permissions.refresh()
        statusItem?.button?.toolTip = permissions.isGranted ? "DockWindow" : "DockWindow needs permissions"
        if permissions.isGranted { tracker.start() } else { tracker.stop() }
    }
    @objc func dumpWindows() { tracker.dumpWindows() }
    func applicationWillTerminate(_ notification: Notification) { permissionTimer?.invalidate(); tracker.stop() }
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
