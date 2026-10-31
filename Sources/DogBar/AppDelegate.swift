import AppKit
import SwiftUI
import DogBarCore
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let updater = UpdateController()
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
    lazy var telemetry = TelemetryService(settings: settings)
    lazy var dock = DockController(tracker: tracker, actions: actions, settings: settings, pinnedApps: pinnedApps, newWindowOpener: newWindowOpener)
    lazy var previews = PreviewController(tracker: tracker, actions: actions, thumbnails: thumbnails, settings: settings, newWindowOpener: newWindowOpener)
    lazy var settingsWindow = SettingsWindowController(settings: settings, permissions: permissions, pinnedApps: pinnedApps,
        onRestoreNativeDock: { [weak self] in self?.restoreNativeDock() }, onShowPermissions: { [weak self] in self?.showOnboarding() })
    var desktopNumbers: [UInt64: Int] = [:]
    var nativeSessionStarted = false
    var replacementActive = false
    var lifecycleTask: Task<Void, Never>?
    var terminating = false
    var subscriptions = Set<AnyCancellable>()
    var previouslyGranted: Bool?
    var lastDockMode: Bool?
    var permissionTimer: Timer?
    var statusItem: NSStatusItem?
    var onboarding: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "DogBar")
        appMenu.addItem(withTitle: "About DogBar", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DogBar", action: #selector(quit), keyEquivalent: "q").target = self
        appMenuItem.submenu = appMenu; mainMenu.addItem(appMenuItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu; mainMenu.addItem(fileItem)
        NSApp.mainMenu = mainMenu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "DogBar") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            item.button?.image = image
        }
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("DogBar")
        let menu = NSMenu()
        let permissionStatus = NSMenuItem(title: "Checking permissions...", action: nil, keyEquivalent: "")
        permissionStatus.identifier = NSUserInterfaceItemIdentifier("permissionStatus")
        permissionStatus.isEnabled = false
        menu.addItem(permissionStatus)
        menu.addItem(.separator())
        menu.addItem(withTitle: "About DogBar", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Pause DogBar", action: #selector(togglePause), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Restore Native Dock", action: #selector(restoreNativeDock), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DogBar", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu; statusItem = item
        if !permissions.isGranted { showOnboarding() }
        startPermissionTimer()
        dock.onHover = { [weak self] item, anchor, screen in self?.previews.hover(item: item, anchor: anchor, screen: screen) }
        dock.onHoverEnded = { [weak self] in self?.previews.hoverEnded() }
        dock.onShowWindows = { [weak self] item, anchor, screen in self?.previews.showWindows(item: item, anchor: anchor, screen: screen) }
        dock.onIconClicked = { [weak self] in self?.previews.dismiss() }
        dock.onContextMenuTrackingChanged = { [weak self] in self?.previews.contextMenuTracking = $0 }
        previews.onVisibilityChanged = { [weak self] visible in
            self?.dock.previewVisible = visible
            if visible { self?.telemetry.featureUsed(.dockPreview) }
        }
        dock.onItemClicked = { [weak self] in self?.telemetry.featureUsed(.dockClick) }
        switcher.$isActive.removeDuplicates().filter { $0 }.sink { [weak self] _ in self?.telemetry.featureUsed(.switcher) }.store(in: &subscriptions)
        tracker.$snapshot.map(\.activeSpaceIDs).removeDuplicates().dropFirst().filter { !$0.isEmpty }.sink { [weak self] _ in
            self?.telemetry.featureUsed(.desktopSwitch)
        }.store(in: &subscriptions)
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.telemetry.settingsChanged() }.store(in: &subscriptions)
        telemetry.start()
        previews.desktopNumber = { [weak self] in self?.desktopNumbers[$0] }
        tracker.$snapshot.map(\.activeSpaceIDs).removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                let numbers = await Task.detached { SpacesService().read(windowIDs: []).desktopNumbers }.value
                self?.desktopNumbers = numbers
            }
        }.store(in: &subscriptions)
        nativeReader.$hoveredItem.receive(on: RunLoop.main).sink { [weak self] item in
            guard let self, !self.replacementActive, !self.settings.useDogBarDock else { return }
            guard let item, let screen = NSScreen.screens.first(where: { $0.frame.intersects(item.frame) }) else { self.previews.hoverEnded(); return }
            self.previews.hover(item: item, screen: screen)
        }.store(in: &subscriptions)
        switcher.onSessionEnded = { [weak self] in self?.hotkey.endSession() }
        tracker.onWindowInventoryChanged = { [weak self] in self?.thumbnails.invalidateShareableContent() }
        tracker.$snapshot.receive(on: RunLoop.main).sink { snapshot in
            DiagnosticsService.record("Snapshot apps=\(snapshot.apps.count) windows=\(snapshot.windows.count) activeSpaces=\(snapshot.activeSpaceIDs)")
        }.store(in: &subscriptions)
        nativeReader.$items.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; self.tracker.setBadges(self.nativeReader.badges)
        }.store(in: &subscriptions)
        permissions.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updateFeatureState() }.store(in: &subscriptions)
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updatePermissions() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: SettingsShortcutRecording.recordingDidChange).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updatePermissions() }.store(in: &subscriptions)
        updatePermissions()
        Log.system.info("DogBar launched")
    }
    private func startPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePermissions() }
        }
        permissionTimer?.tolerance = 0.2
    }
    private func updatePermissions() {
        permissions.refresh()
        updateFeatureState()
    }
    private func updateFeatureState() {
        if previouslyGranted == true && !permissions.isGranted && !terminating { showOnboarding() }
        if permissions.hasCheckedPermissions { previouslyGranted = permissions.isGranted }
        if permissions.isGranted { telemetry.permissionsGranted() }
        if lastDockMode != settings.useDogBarDock {
            previews.dismiss()
            lastDockMode = settings.useDogBarDock
        }
        let desiredPolicy: NSApplication.ActivationPolicy = settings.showDogBarInDock ? .regular : .accessory
        if NSApp.activationPolicy() != desiredPolicy { NSApp.setActivationPolicy(desiredPolicy) }
        statusItem?.isVisible = settings.showMenuBarIcon
        statusItem?.button?.title = ""
        if let status = statusItem?.menu?.items.first(where: { $0.identifier?.rawValue == "permissionStatus" }) {
            status.title = !permissions.hasCheckedPermissions ? "Checking permissions..." : permissions.isGranted ? "Permissions granted" : "Current process access unavailable"
        }
        let subroles = Set(settings.allowedWindowSubroles)
        if tracker.allowedSubroles != subroles { tracker.allowedSubroles = subroles }
        DiagnosticsService.setDebugLogging(settings.debugLogging)
        statusItem?.button?.toolTip = !permissions.hasCheckedPermissions ? "DogBar: checking current process access" : permissions.isGranted ? "DogBar" : "DogBar: current process access is unavailable"
        let enabled = permissions.isGranted && !settings.isPaused && !terminating
        previews.enabled = enabled && settings.previewsEnabled
        switcher.enabled = enabled && settings.switcherEnabled && !SettingsShortcutRecording.isRecording
        var configuration = HotkeyConfiguration()
        configuration.enabled = enabled && settings.switcherEnabled && !SettingsShortcutRecording.isRecording
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
            if settings.switcherEnabled && !SettingsShortcutRecording.isRecording && !hotkey.start() { statusItem?.button?.toolTip = "Window switcher unavailable. Check Accessibility permission." }
        } else { hotkey.stop(); switcher.dismiss(); tracker.stop() }
        if !settings.switcherEnabled || SettingsShortcutRecording.isRecording { hotkey.stop() }
        if enabled { nativeReader.start() } else { nativeReader.stop() }
        reconcileDock()
        if let item = statusItem?.menu?.items.first(where: { $0.action == #selector(togglePause) }) {
            item.title = settings.isPaused ? "Resume DogBar" : "Pause DogBar"
        }
    }
    private var wantsReplacement: Bool { permissions.isGranted && !settings.isPaused && settings.useDogBarDock && !terminating }
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
                        self.previews.dismiss(); self.dock.stop()
                        try await self.nativeDock.restore()
                        self.replacementActive = false
                    }
                }
            } catch {
                self.dock.stop(); self.replacementActive = false
                self.settings.useDogBarDock = false
                do { try await self.nativeDock.restore() } catch { Log.system.error("Native Dock restore failed: \(String(describing: error))") }
                self.showError("DogBar could not update the native Dock. The recovery backup is retained when restoration fails. Try Restore Native Dock again. \(error.localizedDescription)")
            }
            self.lifecycleTask = nil
        }
    }
    @objc func restoreNativeDock() {
        settings.useDogBarDock = false
        dock.stop()
        Task {
            await lifecycleTask?.value
            do { try await nativeDock.restore(); replacementActive = false }
            catch { showError("Native Dock restoration failed. Its backup is retained. \(error.localizedDescription)") }
        }
    }
    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "DogBar"; alert.informativeText = message
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
                startPermissionTimer()
                updatePermissions()
                showError("The native Dock could not be restored. The backup is retained. Try Restore Native Dock before quitting. \(error.localizedDescription)")
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "DogBarPreviewVersion") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let revision = Bundle.main.object(forInfoDictionaryKey: "DogBarBuildRevision") as? String ?? "unbundled"
        let alert = NSAlert(); alert.messageText = "DogBar \(version)"
        alert.informativeText = "Build \(build) · \(revision)\n\nRunning from:\n\(Bundle.main.bundleURL.path)"
        alert.runModal()
    }
    @objc func checkForUpdates() { updater.check() }
    @objc func togglePause() { settings.isPaused.toggle() }
    func applicationWillTerminate(_ notification: Notification) { permissionTimer?.invalidate(); hotkey.stop(); switcher.dismiss(); previews.dismiss(); nativeReader.stop(); dock.stop(); tracker.stop() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showSettings() { onboarding?.orderOut(nil); settingsWindow.show() }
    @objc func showOnboarding() {
        if onboarding == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 530), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Welcome to DogBar"; window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: PermissionsView(permissions: permissions).frame(width: 640, height: 530))
            window.contentViewController = host
            window.setContentSize(NSSize(width: 640, height: 530))
            host.view.frame = NSRect(x: 0, y: 0, width: 640, height: 530)
            host.view.autoresizingMask = [.width, .height]
            host.view.needsLayout = true
            host.view.layoutSubtreeIfNeeded()
            window.center(); onboarding = window
        }
        guard let onboarding else { return }
        onboarding.contentView?.layoutSubtreeIfNeeded()
        onboarding.displayIfNeeded()
        onboarding.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
}
