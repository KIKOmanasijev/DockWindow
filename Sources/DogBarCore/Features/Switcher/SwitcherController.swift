import AppKit
import Combine
import SwiftUI

/// Coordinates a nonactivating switcher session. The coordinator owns permission and tap gating.
@MainActor public final class SwitcherController: ObservableObject {
    /// Set true only after permissions and global feature gating allow switching.
    public var enabled = false { didSet { if !enabled { dismiss(); openingTask?.cancel() } } }
    @Published public private(set) var isActive = false
    /// Called when a session ends, including empty-list cancellation and mouse commit.
    public var onSessionEnded: (() -> Void)?
    /// Optional coordinator-owned error UI. Without it, the reused panel shows an actionable message.
    public var onNewWindowFailure: ((TrackedApp, NewWindowOpener.Result) -> Void)?
    public var isVisible: Bool { panel.isVisible }
    private let tracker: WindowTracker
    private let actions: WindowActions
    private let thumbnails: ThumbnailService
    private let settings: AppSettings
    private let newWindowOpener: NewWindowOpener
    private let refreshSession: VisibleThumbnailSession
    private let panel = SwitcherPanel()
    private let presentation = SwitcherPresentation()
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var openingTask: Task<Void, Never>?
    private var refreshUpdateTask: Task<Void, Never>?
    private var screen: NSScreen?
    private var sessionMode: SwitcherMode = .windows
    private var sessionPID: pid_t?
    private var currentSpaceIDs = Set<UInt64>()
    private var visibleIDs = Set<CGWindowID>()
    private var initialMouse = NSPoint.zero
    private var generation: UInt64 = 0

    public init(tracker: WindowTracker, actions: WindowActions, thumbnails: ThumbnailService, settings: AppSettings, newWindowOpener: NewWindowOpener) {
        self.tracker = tracker; self.actions = actions; self.thumbnails = thumbnails
        self.settings = settings; self.newWindowOpener = newWindowOpener
        refreshSession = VisibleThumbnailSession(service: thumbnails)
        panel.contentView = NSHostingView(rootView: SwitcherView(presentation: presentation, settings: settings, thumbnails: thumbnails))
        presentation.select = { [weak self] id in
            guard let self, self.isActive, NSEvent.mouseLocation != self.initialMouse else { return }
            self.presentation.session.select(id)
        }
        presentation.activate = { [weak self] id in
            guard let self, self.isActive else { return }
            self.presentation.session.select(id); self.commit()
        }
        presentation.operate = { [weak self] window, command in self?.operate(window, command: command, keyboard: false) }
        presentation.zoom = { [weak self] window in
            guard let self, self.isActive else { return }; self.actions.zoom(window)
        }
        presentation.visibility = { [weak self] id, visible in
            guard let self else { return }
            if visible { self.visibleIDs.insert(id) } else { self.visibleIDs.remove(id) }
            self.scheduleRefreshUpdate()
        }
        presentation.dismiss = { [weak self] in self?.dismiss() }
        tracker.$snapshot.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateSnapshot() }.store(in: &subscriptions)
        // Settings sends before persistence. Deliver on the next main-loop turn to read finished values.
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.settingsChanged() }.store(in: &subscriptions)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.dismiss(animated: false) }.store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.settingsChanged() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.dismiss(animated: false)
            }.store(in: &subscriptions)
    }

    public func handle(_ command: SwitcherCommand) {
        guard enabled, settings.switcherEnabled, !settings.isPaused else { dismiss(); return }
        switch command {
        case .begin(let reverse, let sameAppOnly):
            if isActive { presentation.session.move(delta: reverse ? -1 : 1) }
            else { begin(reverse: reverse, sameAppOnly: sameAppOnly) }
        case .cancel: dismiss()
        case .reenableTap: break // The event tap service owns re-enabling its tap.
        default:
            guard isActive else { return }
            switch command {
            case .next, .moveRight: presentation.session.move(delta: 1)
            case .previous, .moveLeft: presentation.session.move(delta: -1)
            case .moveUp: presentation.session.moveVertically(direction: -1, columns: presentation.columns)
            case .moveDown: presentation.session.moveVertically(direction: 1, columns: presentation.columns)
            case .commit: commit()
            case .closeWindow, .minimizeWindow, .hideApp, .quitApp:
                if let item = presentation.session.selectedItem {
                    switch item {
                    case .window(let window): operate(window, command: command)
                    case .windowlessApp(let app):
                        if command == .hideApp, settings.switcherHideWithH { actions.hide(pid: app.pid) }
                        if command == .quitApp, settings.switcherQuitWithQ { actions.quit(pid: app.pid) }
                    }
                }
            default: break
            }
        }
    }

    /// Cancel delayed appearance and captures immediately. Never focuses a target.
    public func dismiss(animated: Bool = true) {
        generation &+= 1
        openingTask?.cancel(); openingTask = nil
        appearanceTask?.cancel(); appearanceTask = nil
        refreshUpdateTask?.cancel(); refreshUpdateTask = nil
        refreshSession.stop()
        let wasActive = isActive
        isActive = false; sessionPID = nil
        hideTask?.cancel()
        if animated, wasActive, enabled, settings.switcherEnabled, !settings.isPaused, panel.isVisible, !Theme.reducesMotion(settings) {
            presentation.revealed = false
            let token = generation
            hideTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.panel.orderOut(nil); self.hideTask = nil
            }
        } else { hideTask = nil; presentation.revealed = false; panel.orderOut(nil) }
        if wasActive { onSessionEnded?() }
    }

    private func begin(reverse: Bool, sameAppOnly: Bool) {
        hideTask?.cancel(); panel.orderOut(nil); presentation.revealed = false
        openingTask?.cancel()
        generation &+= 1
        screen = Self.mouseScreen(); initialMouse = NSEvent.mouseLocation
        sessionPID = sameAppOnly ? tracker.snapshot.apps.first(where: \.isFrontmost)?.pid : nil
        // An unknown frontmost app cannot safely produce a same-app session.
        guard !sameAppOnly || sessionPID != nil else { onSessionEnded?(); return }
        sessionMode = sameAppOnly ? .windows : settings.switcherMode
        presentation.appMode = sessionMode == .apps
        presentation.message = nil; presentation.apps = tracker.snapshot.apps
        let items = filteredItems()
        guard !items.isEmpty else { onSessionEnded?(); return }
        presentation.session.begin(items: items, reverse: reverse)
        isActive = true; layout()
        let token = generation
        let delay = min(5, max(0, settings.switcherAppearanceDelay))
        if delay == 0 { reveal(); return }
        appearanceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, self.generation == token, self.isActive else { return }
            self.reveal()
        }
    }
    private func filteredItems() -> [SwitcherItem] {
        let snapshot = tracker.snapshot
        let displayID = screen.flatMap(Self.displayIdentifier)
        currentSpaceIDs = SpacePolicy.currentSpaceIDs(snapshot: snapshot, displayID: displayID,
                                                      separateSpaces: NSScreen.screensHaveSeparateSpaces,
                                                      allDisplays: settings.switcherScreens == .all)
        if sessionMode == .apps {
            return SwitcherPolicy.applications(snapshot: snapshot, includeHidden: settings.switcherIncludeHiddenApps)
        }
        let filter = WindowFilter(scope: settings.switcherScope, currentSpaceIDs: currentSpaceIDs,
                                  includeMinimized: settings.switcherIncludeMinimized, includeHiddenApps: settings.switcherIncludeHiddenApps,
                                  pid: sessionPID, displayFrame: settings.switcherScreens == .withMouse ? screen.map(Self.quartzFrame) : nil)
        return SwitcherPolicy.items(snapshot: snapshot, filter: filter, showWindowlessApps: settings.switcherShowWindowlessApps, frontmostPID: sessionPID)
    }
    private func updateSnapshot() {
        guard isActive else { return }
        presentation.apps = tracker.snapshot.apps
        presentation.session.update(items: filteredItems())
        guard !presentation.session.items.isEmpty else { dismiss(); return }
        layout(); scheduleRefreshUpdate()
    }
    private func settingsChanged() {
        if !isActive, hideTask != nil, Theme.reducesMotion(settings) { dismiss(animated: false) }
        guard enabled, settings.switcherEnabled, !settings.isPaused else { dismiss(); return }
        if isActive, sessionPID == nil, sessionMode != settings.switcherMode { dismiss(animated: false); return }
        panel.appearance = Theme.appearance(settings.theme)
        updateSnapshot()
    }
    private func reveal() {
        guard isActive else { return }
        panel.appearance = Theme.appearance(settings.theme)
        panel.orderFrontRegardless()
        presentation.revealed = true
        scheduleRefreshUpdate()
    }
    private func commit() {
        let item = presentation.session.selectedItem
        let spaces = currentSpaceIDs
        let scope = settings.switcherScope
        let targetSpace = SpacePolicy.currentSpaceIDs(snapshot: tracker.snapshot, displayID: screen.flatMap(Self.displayIdentifier), separateSpaces: NSScreen.screensHaveSeparateSpaces).sorted().first ?? 0
        dismiss()
        guard let item else { return }
        switch item {
        case .window(let window):
            if scope == .currentDesktop, let space = spaces.first(where: { SpacePolicy.membership(of: window).contains($0) }) {
                _ = actions.focus(window, requiringSpace: space)
            } else { actions.focus(window) }
        case .windowlessApp(let app):
            if sessionMode == .apps {
                NSRunningApplication(processIdentifier: app.pid)?.activate(options: [.activateAllWindows])
                return
            }
            let rule = settings.newWindowRule(for: app.bundleIdentifier ?? "")
            let token = generation
            openingTask = Task { [weak self] in
                guard let self else { return }
                let result = await self.newWindowOpener.open(app: app, onSpace: targetSpace, rule: rule)
                guard !Task.isCancelled, self.generation == token else { return }
                switch result {
                case .opened, .cancelled: break
                case .failed, .unknownSpace:
                    if let report = self.onNewWindowFailure { report(app, result) }
                    else { self.showOpeningFailure(app: app) }
                }
            }
        }
    }
    private func showOpeningFailure(app: TrackedApp) {
        hideTask?.cancel(); hideTask = nil
        presentation.session.update(items: [])
        presentation.message = "Could not confirm a new \(app.name) window on this desktop. Use the app's File menu to open a window here, then try again."
        presentation.size = CGSize(width: 460, height: 160)
        positionPanel(); panel.orderFrontRegardless(); presentation.revealed = true
    }
    private func operate(_ window: TrackedWindow, command: SwitcherCommand, keyboard: Bool = true) {
        guard isActive else { return }
        switch command {
        case .closeWindow: if !keyboard || settings.switcherCloseWithW { actions.close(window) }
        case .minimizeWindow: if !keyboard || settings.switcherMinimizeWithM { actions.minimize(window) }
        case .hideApp: if !keyboard || settings.switcherHideWithH { actions.hide(pid: window.pid) }
        case .quitApp: if !keyboard || settings.switcherQuitWithQ { actions.quit(pid: window.pid) }
        default: break
        }
    }
    private func layout() {
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxWidth = max(100, bounds.width * 0.9)
        let maxHeight = max(100, bounds.height * 0.85)
        let width = sessionMode == .apps ? CGFloat(116) : min(max(64, settings.switcherThumbnailWidth), maxWidth - 56)
        let height = sessionMode == .apps ? CGFloat(96) : min(max(48, settings.switcherThumbnailHeight), maxHeight - 104)
        let tileSize = SwitcherTileMetrics.size(thumbnail: CGSize(width: width, height: height))
        let columns = SwitcherTileMetrics.columns(availableWidth: maxWidth, tileWidth: tileSize.width,
                                                  itemCount: presentation.session.items.count, maximum: settings.switcherMaxTilesPerRow)
        let rows = max(1, (presentation.session.items.count + columns - 1) / columns)
        presentation.columns = columns
        presentation.thumbnailSize = CGSize(width: width, height: height)
        presentation.size = CGSize(width: min(maxWidth, CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * 12 + 40),
                                   height: min(maxHeight, CGFloat(rows) * tileSize.height + CGFloat(rows - 1) * 12 + 40))
        positionPanel()
    }
    private func positionPanel() {
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        panel.setFrame(NSRect(x: frame.midX - presentation.size.width / 2, y: frame.midY - presentation.size.height / 2,
                              width: presentation.size.width, height: presentation.size.height), display: panel.isVisible)
    }
    private func scheduleRefreshUpdate() {
        refreshUpdateTask?.cancel()
        refreshUpdateTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.isActive, self.panel.isVisible else { return }
            let eligible = Set(self.presentation.session.items.compactMap { item -> CGWindowID? in if case .window(let window) = item { return window.id }; return nil })
            self.refreshSession.update(windowIDs: self.visibleIDs.intersection(eligible), interval: self.settings.thumbnailRefreshInterval,
                                       size: self.presentation.thumbnailSize, scale: self.screen?.backingScaleFactor ?? 2)
        }
    }
    deinit {
        appearanceTask?.cancel(); hideTask?.cancel(); openingTask?.cancel(); refreshUpdateTask?.cancel()
    }
    private static func mouseScreen() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }
    private static func displayIdentifier(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    /// Tracker window frames use Quartz's top-left origin, NSScreen uses AppKit's bottom-left origin.
    private static func quartzFrame(_ screen: NSScreen) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    }
}
