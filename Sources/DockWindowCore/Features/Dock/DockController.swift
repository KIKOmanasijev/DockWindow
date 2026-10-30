import AppKit
import Combine

/// Replacement Dock presentation and interactions. The coordinator owns permissions and native Dock restoration.
@MainActor public final class DockController {
    /// AppKit global icon frame and its display, updated during magnification. Preview code owns hover delay.
    public var onHover: ((DockItem, CGRect, NSScreen) -> Void)?
    public var onHoverEnded: (() -> Void)?
    /// Requests a preview pinned open from the context menu.
    public var onShowWindows: ((DockItem, CGRect, NSScreen) -> Void)?
    public var onIconClicked: (() -> Void)?
    /// If absent, actionable failures appear in an NSAlert.
    public var onError: ((String) -> Void)?
    public var previewVisible = false { didSet { guard previewVisible != oldValue else { return }; view.previewVisible = previewVisible; if previewVisible { hideTask?.cancel(); hideTask = nil } else { updatePointer() } } }
    private let tracker: WindowTracker
    private let actions: WindowActions
    private let settings: AppSettings
    private let pins: PinnedAppsStore
    private let opener: NewWindowOpener
    private let panel = DockPanel()
    private let view: DockView
    private var subscriptions: Set<AnyCancellable> = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lifecycleGeneration: UInt64 = 0
    private var screen: NSScreen?
    private var shownFrame = CGRect.zero
    private var menuVisible = false
    private var hidden = false
    private var started = false
    private var hideTask: Task<Void, Never>?
    private var openingTasks: [String: Task<Void, Never>] = [:]
    private var launching: Set<String> = []
    private var removedRunning: Set<String> = []
    private var runningOrder: [String] = []
    private var scrollState: (id: String, index: Int, time: TimeInterval)?
    private var hoverItem: DockItem?
        private let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")

    public init(tracker: WindowTracker, actions: WindowActions, settings: AppSettings,
                pinnedApps: PinnedAppsStore, newWindowOpener: NewWindowOpener) {
        self.tracker = tracker; self.actions = actions; self.settings = settings; pins = pinnedApps; opener = newWindowOpener
        view = DockView(settings: settings); panel.contentView = view
        view.onClick = { [weak self] in self?.click($0) }
        view.onMenu = { [weak self] in self?.showMenu(item: $0, event: $1) }
        view.onHover = { [weak self] item, rect in self?.hover(item: item, rect: rect) }
        view.onReorder = { [weak self] item, index, remove in self?.reorder(item, at: index, remove: remove) }
        view.onFiles = { [weak self] in self?.openFiles($0, item: $1) }
    }
    /// Call only after the coordinator has enabled the native Dock mitigation and permission gates.
    public func start() {
        guard !started else { return }; started = true; lifecycleGeneration &+= 1
        tracker.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.reload() }.store(in: &subscriptions)
        pins.$apps.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .flagsChanged, .scrollWheel]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updatePointer()
            if event.type == .scrollWheel, self?.scroll(event) == true { return nil }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp]) { [weak self] _ in self?.updatePointer() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screen = nil; self?.reload() }
        }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hideTask?.cancel(); self.hideTask = nil
                    self.view.stopTracking()
                    if notification.name == NSWorkspace.willSleepNotification {
                        self.lifecycleGeneration &+= 1
                        for task in self.openingTasks.values { task.cancel() }; self.openingTasks.removeAll()
                        self.panel.orderOut(nil)
                    }
                    else { self.screen = nil; self.reload() }
                }
            })
        }
        reload(); updatePointer()
    }
    /// Cancels pending UI work and opening sequences. Does not stop shared services or restore native preferences.
    public func stop() {
        guard started else { return }; started = false; lifecycleGeneration &+= 1
        hideTask?.cancel(); hideTask = nil
        for task in openingTasks.values { task.cancel() }; openingTasks.removeAll()
        for monitor in [localMonitor, globalMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        localMonitor = nil; globalMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; screenObserver = nil
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }; launchObserver = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; workspaceObservers = []
        subscriptions.removeAll(); view.launching = []; view.stopTracking(); panel.orderOut(nil); panel.ignoresMouseEvents = true
        launching.removeAll(); removedRunning.removeAll(); hoverItem = nil; hidden = false; previewVisible = false; scrollState = nil
    }
    private func display() -> NSScreen? {
        if settings.dockDisplay == .withMouse {
            return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.screens.first
        }
        // The first screen is the menu-bar/primary display. NSScreen.main follows key-window focus.
        return NSScreen.screens.first
    }
    private var spaces: Set<UInt64> {
        let displayID = screen.flatMap { screen -> String? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
            return CFUUIDCreateString(nil, uuid) as String
        }
        return SpacePolicy.currentSpaceIDs(snapshot: tracker.snapshot, displayID: displayID, separateSpaces: NSScreen.screensHaveSeparateSpaces)
    }
    private func reload() {
        guard started else { return }
        guard settings.useDockWindowDock, !settings.isPaused else {
            hideTask?.cancel(); hideTask = nil
            for task in openingTasks.values { task.cancel() }; openingTasks.removeAll()
            lifecycleGeneration &+= 1
            panel.orderOut(nil); panel.ignoresMouseEvents = true; view.stopTracking(); return
        }
        guard let nextScreen = display() else { hideTask?.cancel(); hideTask = nil; view.stopTracking(); panel.orderOut(nil); return }
        if screen !== nextScreen {
            hideTask?.cancel(); hideTask = nil; view.stopTracking()
        }
        screen = nextScreen
        shownFrame = DockLayout.panelFrame(screen: nextScreen.frame, position: settings.dockPosition, depth: settings.dockPosition == .bottom ? max(210, settings.magnificationSize + 85) : max(360, settings.magnificationSize + 220))
        if !settings.autohide { hidden = false; hideTask?.cancel(); hideTask = nil }
        panel.setFrame(hidden ? DockLayout.hiddenFrame(shownFrame, position: settings.dockPosition) : shownFrame, display: true)
        let options = DockCompositionOptions(scope: settings.dockScope, currentSpaceIDs: spaces, otherDesktopApps: settings.otherDesktopApps,
                                              includeMinimized: settings.includeMinimizedInDock,
                                              showWindowlessAppsOnLastActiveDesktop: settings.showWindowlessAppsOnLastActiveDesktop, showTrash: settings.showTrash)
        var items = DockCompositionPolicy.items(snapshot: tracker.snapshot, pinned: pins.apps, options: options)
        let runningIDs = Set(tracker.snapshot.apps.map { $0.bundleIdentifier ?? "pid:\($0.pid)" })
        removedRunning.formIntersection(runningIDs)
        items.removeAll { !$0.isPinned && removedRunning.contains($0.id) }
        let unpinned = items.filter { $0.kind == .application && !$0.isPinned }.sorted {
            (runningOrder.firstIndex(of: $0.id) ?? Int.max) < (runningOrder.firstIndex(of: $1.id) ?? Int.max)
        }
        items = items.filter { $0.kind == .application && $0.isPinned } + unpinned + items.filter { $0.kind != .application }
        if !view.isDragging { view.items = items }
        for item in items {
            let path = item.pinnedApp?.url ?? item.app?.bundleURL
            if let icon = item.app?.icon { view.images[item.id] = icon }
            else if let path, view.images[item.id] == nil { view.images[item.id] = NSWorkspace.shared.icon(forFile: path.path) }
            if item.kind == .trash { view.images[item.id] = NSWorkspace.shared.icon(forFile: trashURL.path) }
            view.indicators[item.id] = DotPolicy.indicators(windows: tracker.snapshot.windows,
                filter: WindowFilter(scope: settings.dockScope, currentSpaceIDs: spaces, includeMinimized: settings.includeMinimizedInCount, pid: item.app?.pid ?? -1),
                style: settings.indicatorStyle, maxDots: settings.maxDots, isRunning: item.app != nil, showRunningState: settings.showRunningState)
            if let app = item.app, NSRunningApplication(processIdentifier: app.pid)?.isFinishedLaunching == true { launching.remove(item.id) }
        }
        view.images = view.images.filter { key, _ in items.contains { $0.id == key } }
        view.launching = launching; view.render()
        if !panel.isVisible { panel.orderFrontRegardless() }
        updatePointer()
    }
    private func updatePointer() {
        guard started, settings.useDockWindowDock, !settings.isPaused, let screen else { return }
        if settings.dockDisplay == .withMouse, !screen.frame.contains(NSEvent.mouseLocation), !view.isDragging, !previewVisible {
            if let next = display(), next !== screen { self.screen = next; reload(); return }
        }
        let global = NSEvent.mouseLocation
        let point = view.convert(panel.convertPoint(fromScreen: global), from: nil)
        let inside = !hidden && view.containsInteractivePoint(point)
        panel.ignoresMouseEvents = !inside && !view.ownsMouseSequence
        view.track(inside || view.isDragging ? point : nil)
        let edge = DockLayout.touchesEdge(global, screen: screen.frame, position: settings.dockPosition)
        if inside || edge || previewVisible || view.ownsMouseSequence || menuVisible {
            hideTask?.cancel(); hideTask = nil
            if hidden { setHidden(false) }
        } else if settings.autohide, !hidden, hideTask == nil {
            hideTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(0, min(10, self.settings.autohideDelay)) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.hideTask = nil; self.setHidden(true)
            }
        }
    }
    private func setHidden(_ value: Bool) {
        hidden = value
        if value { view.stopTracking(); panel.ignoresMouseEvents = true }
        if Theme.reducesMotion(settings) {
            panel.setFrame(value ? DockLayout.hiddenFrame(shownFrame, position: settings.dockPosition) : shownFrame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.reducesMotion(settings) ? 0 : 0.18
            panel.animator().setFrame(value ? DockLayout.hiddenFrame(shownFrame, position: settings.dockPosition) : shownFrame, display: true)
        }
    }
    private func hover(item: DockItem?, rect: CGRect) {
        let wasHovering = hoverItem?.kind == .application
        hoverItem = item
        guard let item, item.kind == .application, let screen else { if wasHovering { onHoverEnded?() }; return }
        let frame = panel.convertToScreen(view.convert(rect, to: nil))
        onHover?(item, frame, screen)
    }
    private func localWindows(_ item: DockItem) -> [TrackedWindow] {
        guard let pid = item.app?.pid else { return [] }
        return WindowFilter(currentSpaceIDs: spaces, pid: pid).apply(to: tracker.snapshot.windows)
    }
    private func click(_ item: DockItem) {
        onIconClicked?()
        if item.kind == .trash { NSWorkspace.shared.open(trashURL); return }
        switch DockClickPolicy.action(app: item.app, windows: tracker.snapshot.windows, currentSpaceIDs: spaces, activeBehavior: settings.activeAppClickBehavior) {
        case .focus(let id): focus(id)
        case .cycle:
            if let pid = item.app?.pid, let id = DockClickPolicy.cycleTarget(windows: tracker.snapshot.windows, pid: pid, currentSpaceIDs: spaces, focusedWindowID: localWindows(item).first?.id) { focus(id) }
        case .openNewWindowHere: openNew(item)
        case .launch: launch(item)
        case .minimize: if let window = localWindows(item).first { actions.minimize(window) }
        case .hide: if let pid = item.app?.pid { actions.hide(pid: pid) }
        case .none: break
        }
    }
    private func focus(_ id: CGWindowID) {
        guard let window = tracker.snapshot.windows.first(where: { $0.id == id }) else { return }
        guard let target = spaces.first(where: { SpacePolicy.membership(of: window).contains($0) }) else {
            report("Cannot confirm this window's desktop. Wait for the window list to refresh, then try again."); return
        }
        let key = "focus"
        openingTasks[key]?.cancel()
        openingTasks[key] = Task { [weak self] in
            guard let self else { return }
            let success = await self.actions.focusVerified(window, requiringSpace: target)
            guard !Task.isCancelled, self.started else { return }
            self.openingTasks[key] = nil
            if !success { self.report("Could not confirm focus on this desktop. Select the window from the application's Window menu, then try again.") }
        }
    }
    private func openNew(_ item: DockItem) {
        let app = item.app
        let url = item.pinnedApp?.url
        guard app != nil || url != nil else { report("This application's location is unavailable. Pin it again from Finder."); return }
        let name = app?.name ?? url?.deletingPathExtension().lastPathComponent ?? "application"
        let rule = settings.newWindowRule(for: app?.bundleIdentifier ?? item.pinnedApp?.bundleIdentifier ?? "")
        guard let space = spaces.sorted().first else { report("The current desktop is unavailable. Open a window from the app's File menu, then try again."); return }
        guard openingTasks[item.id] == nil else { return }
        openingTasks[item.id] = Task { [weak self] in
            guard let self else { return }
            let result: NewWindowOpener.Result
            if let app { result = await self.opener.open(app: app, onSpace: space, rule: rule) }
            else if let url { result = await self.opener.openPinned(bundleURL: url, onSpace: space, rule: rule) }
            else { return }
            guard !Task.isCancelled, self.started else { return }
            self.openingTasks[item.id] = nil
            switch result {
            case .opened, .cancelled: break
            case .failed, .unknownSpace: self.report("Could not confirm a new \(name) window on this desktop. Use the app's File menu to open a window here, then try again.")
            }
        }
    }
    private func launch(_ item: DockItem) {
        guard let url = item.pinnedApp?.url ?? item.app?.bundleURL else { report("This application's location is unavailable. Pin it again from Finder."); return }
        guard !launching.contains(item.id) else { return }
        launching.insert(item.id); view.launching = launching; view.render()
        let token = lifecycleGeneration
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self, self.started, self.lifecycleGeneration == token else { return }
                self.launching.remove(item.id); self.reload()
                if let error, self.started { self.report("Could not open \(url.lastPathComponent): \(error.localizedDescription). Check its location in Finder.") }
            }
        }
    }
    private func scroll(_ event: NSEvent) -> Bool {
        guard settings.scrollToCycleWindows, event.window === panel, let item = hoverItem else { return false }
        let windows = localWindows(item)
        guard !windows.isEmpty, abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX) > 0.5 else { return false }
        let now = event.timestamp
        if let state = scrollState, state.id == item.id, now - state.time < 0.18 { return true }
        let previous = scrollState?.id == item.id ? scrollState?.index ?? 0 : 0
        let delta = event.scrollingDeltaY + event.scrollingDeltaX > 0 ? 1 : -1
        let index = ((previous + delta) % windows.count + windows.count) % windows.count
        scrollState = (item.id, index, now); focus(windows[index].id); return true
    }
    private func reorder(_ item: DockItem, at index: Int, remove: Bool) {
        guard item.id != DockCompositionPolicy.finderBundleIdentifier else { return }
        if remove {
            pins.unpin(bundleIdentifier: item.id)
            if item.app != nil { removedRunning.insert(item.id) }
        } else {
            // Count pins before the insertion in the transient visual order. Finder is immutable.
            let preceding = view.items.prefix(max(1, index)).filter { $0.isPinned && $0.id != item.id && $0.id != DockCompositionPolicy.finderBundleIdentifier }.count
            let originalPinCount = pins.apps.filter { $0.bundleIdentifier != DockCompositionPolicy.finderBundleIdentifier && $0.bundleIdentifier != item.id }.count
            let pinnedRegion = item.isPinned || index <= originalPinCount + 1
            if pinnedRegion, let url = item.pinnedApp?.url ?? item.app?.bundleURL {
                pins.unpin(bundleIdentifier: item.id)
                let offset = pins.apps.first?.bundleIdentifier == DockCompositionPolicy.finderBundleIdentifier ? 1 : 0
                pins.pin(bundleIdentifier: item.id, url: url, at: preceding + offset)
            }
            runningOrder = view.items.filter { !$0.isPinned && $0.kind == .application }.map(\.id)
        }
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }
    private func openFiles(_ urls: [URL], item: DockItem) {
        if item.kind == .trash {
            Task { [weak self] in
                let failure: String? = await Task.detached {
                    var errors: [String] = []
                    for url in urls { do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") } }
                    return errors.isEmpty ? nil : errors.joined(separator: "\n")
                }.value
                if let failure { self?.report("Some files could not be moved to Trash:\n\(failure)") }; self?.reload()
            }
        } else if let url = item.pinnedApp?.url ?? item.app?.bundleURL {
            NSWorkspace.shared.open(urls, withApplicationAt: url, configuration: .init()) { [weak self] _, error in
                if let error { Task { @MainActor [weak self] in self?.report("Could not open these files: \(error.localizedDescription). Try opening them from the app's File menu.") } }
            }
        }
    }
    private func showMenu(item: DockItem, event: NSEvent) {
        onIconClicked?(); hideTask?.cancel(); hideTask = nil; menuVisible = true
        let menu = NSMenu(); menu.autoenablesItems = false
        func add(_ title: String, action: @escaping () -> Void) -> DockMenuItem {
            let entry = DockMenuItem(title: title, handler: action); menu.addItem(entry); return entry
        }
        if item.kind == .trash {
            _ = add("Open Trash") { [weak self] in if let self { NSWorkspace.shared.open(self.trashURL) } }
            _ = add("Empty Trash...") { [weak self] in self?.emptyTrash() }
        } else {
            for window in localWindows(item) { _ = add(window.title.isEmpty ? "Untitled Window" : window.title) { [weak self] in self?.focus(window.id) } }
            if !localWindows(item).isEmpty { menu.addItem(.separator()) }
            _ = add("New Window") { [weak self] in self?.openNew(item) }
            let show = add("Show All Windows") { [weak self] in
                guard let self, let screen = self.screen, let iconFrame = self.view.iconFrame(for: item.id) else { return }
                let rect = self.view.convert(iconFrame, to: nil)
                self.onShowWindows?(item, self.panel.convertToScreen(rect), screen)
            }
            show.isEnabled = onShowWindows != nil
            if let app = item.app {
                _ = add("Hide") { [weak self] in self?.actions.hide(pid: app.pid) }
                _ = add("Quit") { [weak self] in self?.actions.quit(pid: app.pid) }
                let force = add("Force Quit") { [weak self] in self?.actions.quit(pid: app.pid, force: true) }
                force.isAlternate = true; force.keyEquivalentModifierMask = .option
            }
            menu.addItem(.separator())
            let options = NSMenu(); options.autoenablesItems = false; let root = NSMenuItem(title: "Options", action: nil, keyEquivalent: ""); root.submenu = options; menu.addItem(root)
            let pin = DockMenuItem(title: item.isPinned ? "Remove from Dock" : "Keep in Dock") { [weak self] in
                guard let self else { return }
                if item.isPinned { self.pins.unpin(bundleIdentifier: item.id) }
                else if let url = item.app?.bundleURL, let identifier = item.app?.bundleIdentifier { self.pins.pin(bundleIdentifier: identifier, url: url) }
            }
            pin.isEnabled = item.id != DockCompositionPolicy.finderBundleIdentifier && (item.isPinned || item.app?.bundleIdentifier != nil)
            options.addItem(pin)
            _ = add("Show in Finder") {
                if let url = item.pinnedApp?.url ?? item.app?.bundleURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        menuVisible = false; updatePointer()
    }
    private func emptyTrash() {
        let alert = NSAlert(); alert.messageText = "Empty Trash?"; alert.informativeText = "These items will be permanently deleted."
        alert.addButton(withTitle: "Empty Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { [weak self] in
            let failure: String? = await Task.detached {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: "tell application \"Finder\" to empty trash") else { return "The Finder command could not be created." }
                _ = script.executeAndReturnError(&error)
                return error.map { String(describing: $0) }
            }.value
            if let failure { self?.report("Could not empty Trash. Open Trash in Finder and try again. \(failure)") }; self?.reload()
        }
    }
    deinit {
        hideTask?.cancel()
        for task in openingTasks.values { task.cancel() }
        for monitor in [localMonitor, globalMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        let surface = view
        Task { @MainActor in surface.stopTracking() }
    }
    private func report(_ message: String) {
        if let onError { onError(message) }
        else { let alert = NSAlert(); alert.messageText = "DockWindow"; alert.informativeText = message; alert.addButton(withTitle: "OK"); alert.runModal() }
    }
}

@MainActor private final class DockMenuItem: NSMenuItem {
    let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler; super.init(title: title, action: #selector(invoke), keyEquivalent: ""); target = self
    }
    required init(coder: NSCoder) { fatalError("Dock menus are constructed programmatically") }
    @objc private func invoke() { handler() }
}
