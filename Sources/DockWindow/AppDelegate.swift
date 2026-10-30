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
    let nativeDock = NativeDockController()
    let nativeReader = NativeDockReader()
    let pinnedApps = PinnedAppsStore()
    lazy var dock = DockController(tracker: tracker, actions: actions, settings: settings, pinnedApps: pinnedApps, newWindowOpener: newWindowOpener)
    var nativeSessionStarted = false
    var replacementActive = false
    var lifecycleTask: Task<Void, Never>?
    var terminating = false
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
        menu.addItem(withTitle: "Restore Native Dock", action: #selector(restoreNativeDock), keyEquivalent: "").target = self
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
        nativeReader.$items.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; self.tracker.setBadges(self.nativeReader.badges)
        }.store(in: &subscriptions)
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updatePermissions() }.store(in: &subscriptions)
        updatePermissions()
        Log.system.info("DockWindow launched")
    }
    private func updatePermissions() {
        permissions.refresh()
        statusItem?.button?.toolTip = permissions.isGranted ? "DockWindow" : "DockWindow needs permissions"
        let enabled = permissions.isGranted && !settings.isPaused && !terminating
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
        if enabled { nativeReader.start() } else { nativeReader.stop() }
        reconcileDock()
        if let item = statusItem?.menu?.items.first(where: { $0.action == #selector(togglePause) }) {
            item.title = settings.isPaused ? "Resume DockWindow" : "Pause DockWindow"
        }
    }
    private var wantsReplacement: Bool { permissions.isGranted && !settings.isPaused && settings.useDockWindowDock && !terminating }
    private func reconcileDock() {
        guard lifecycleTask == nil else { return }
        guard !nativeSessionStarted || replacementActive != wantsReplacement else { return }
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !self.nativeSessionStarted {
                    // Recover stale preferences before any invasive feature is enabled.
                    try await self.nativeDock.beginSession(dockEnabled: false)
                    self.nativeSessionStarted = true
                }
                while self.replacementActive != self.wantsReplacement {
                    if self.wantsReplacement {
                        try await self.nativeDock.hide()
                        // Permission or preference may have changed while defaults was running.
                        if self.wantsReplacement { self.dock.start(); self.replacementActive = true }
                        else { try await self.nativeDock.restore() }
                    } else {
                        self.dock.stop()
                        try await self.nativeDock.restore()
                        self.replacementActive = false
                    }
                }
            } catch {
                self.dock.stop(); self.replacementActive = false
                self.settings.useDockWindowDock = false
                do { try await self.nativeDock.restore() } catch { Log.system.error("Native Dock restore failed: \(String(describing: error))") }
                self.showError("DockWindow could not update the native Dock. The recovery backup is retained when restoration fails. Try Restore Native Dock again. \(error.localizedDescription)")
            }
            self.lifecycleTask = nil
        }
    }
    @objc func restoreNativeDock() {
        settings.useDockWindowDock = false
        dock.stop()
        Task {
            await lifecycleTask?.value
            do { try await nativeDock.restore(); replacementActive = false }
            catch { showError("Native Dock restoration failed. Its backup is retained. \(error.localizedDescription)") }
        }
    }
    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "DockWindow"; alert.informativeText = message
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        permissionTimer?.invalidate(); updatePermissions(); dock.stop()
        Task {
            await lifecycleTask?.value
            do { try await nativeDock.endSession(); NSApp.reply(toApplicationShouldTerminate: true) }
            catch {
                terminating = false
                showError("The native Dock could not be restored. The backup is retained. Try Restore Native Dock before quitting. \(error.localizedDescription)")
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
    @objc func togglePause() { settings.isPaused.toggle() }
    @objc func dumpWindows() { tracker.dumpWindows() }
    func applicationWillTerminate(_ notification: Notification) { permissionTimer?.invalidate(); hotkey.stop(); switcher.dismiss(); tracker.stop() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showOnboarding() {
        if onboarding == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 530), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Welcome to DockWindow"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PermissionsView(permissions: permissions)); window.center(); onboarding = window
        }
        onboarding?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showOnboarding(); return true }
}
