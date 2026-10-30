import AppKit
import Combine
import SwiftUI

/// Owns delayed hover, pointer bridging and an independent visible capture lease.
/// The coordinator supplies permission gating and both Dock adapters.
@MainActor public final class PreviewController {
    public var enabled = false { didSet { if !enabled { dismiss() } } }
    public var onVisibilityChanged: ((Bool) -> Void)?
    public var onError: ((String) -> Void)?
    /// Optional topology ordinal lookup. Space IDs are not desktop numbers.
    public var desktopNumber: ((UInt64) -> Int?)?
    public var isVisible: Bool { panel.isVisible }
    private let tracker: WindowTracker
    private let actions: WindowActions
    private let thumbnails: ThumbnailService
    private let settings: AppSettings
    private let newWindowOpener: NewWindowOpener
    private let captures: VisibleThumbnailSession
    private let panel = PreviewPanel()
    private let presentation = PreviewPresentation()
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var openingTask: Task<Void, Never>?
    private var captureUpdateTask: Task<Void, Never>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var item: DockItem?
    private var anchor: CGRect = .zero
    private var screen: NSScreen?
    private var edge: DockPosition = .bottom
    private var pinned = false
    private var native = false
    private var visibleIDs = Set<CGWindowID>()
    private var currentSpaces = Set<UInt64>()
    private var generation: UInt64 = 0

    public init(tracker: WindowTracker, actions: WindowActions, thumbnails: ThumbnailService, settings: AppSettings, newWindowOpener: NewWindowOpener) {
        self.tracker = tracker; self.actions = actions; self.thumbnails = thumbnails
        self.settings = settings; self.newWindowOpener = newWindowOpener
        captures = VisibleThumbnailSession(service: thumbnails)
        panel.contentView = NSHostingView(rootView: PreviewView(presentation: presentation, settings: settings, thumbnails: thumbnails))
        presentation.activate = { [weak self] in self?.activate($0) }
        presentation.close = { [weak self] in self?.actions.close($0) }
        presentation.minimize = { [weak self] in self?.actions.minimize($0) }
        presentation.zoom = { [weak self] in self?.actions.zoom($0) }
        presentation.open = { [weak self] in self?.openWindow() }
        presentation.visibility = { [weak self] id, visible in
            guard let self else { return }
            if visible { self.visibleIDs.insert(id) } else { self.visibleIDs.remove(id) }
            self.scheduleCaptures()
        }
        tracker.$snapshot.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            guard let self else { return }
            guard self.allowed else { self.dismiss(); return }
            if self.item != nil { self.update() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.dismiss() }.store(in: &subscriptions)
    }

    public func hover(item: DockItem, anchor: CGRect, screen: NSScreen) {
        receive(item: item, anchor: anchor, screen: screen, native: false, pin: false)
    }
    /// Native reader frames are already AppKit global points. Reject stale selected icons.
    public func hover(item: NativeDockItem, screen: NSScreen) {
        guard item.frame.contains(NSEvent.mouseLocation) else { hoverEnded(); return }
        let app = tracker.snapshot.apps.first { candidate in
            if let bundle = item.bundleIdentifier { return candidate.bundleIdentifier == bundle }
            return candidate.bundleURL == item.bundleURL && item.bundleURL != nil
        }
        let pin = item.bundleURL.flatMap { url in item.bundleIdentifier.map { PinnedApp(bundleIdentifier: $0, url: url) } }
        receive(item: DockItem(id: item.id, app: app, pinnedApp: pin), anchor: item.frame, screen: screen, native: true, pin: false)
    }
    public func hoverEnded() {
        guard !pinned else { return }
        pointerMoved()
    }
    public func showWindows(item: DockItem, anchor: CGRect, screen: NSScreen) {
        receive(item: item, anchor: anchor, screen: screen, native: false, pin: true)
    }
    public func dismiss() {
        generation &+= 1
        appearanceTask?.cancel(); appearanceTask = nil
        closeTask?.cancel(); closeTask = nil
        openingTask?.cancel(); openingTask = nil
        captureUpdateTask?.cancel(); captureUpdateTask = nil
        captures.stop(); visibleIDs = []
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        let visible = panel.isVisible
        panel.orderOut(nil); item = nil; screen = nil; pinned = false
        presentation.opening = false; presentation.message = nil
        if visible { onVisibilityChanged?(false) }
    }
    private var allowed: Bool { enabled && settings.previewsEnabled && !settings.isPaused }
    private func receive(item: DockItem, anchor: CGRect, screen: NSScreen, native: Bool, pin: Bool) {
        guard allowed, item.kind == .application else { return }
        // Show All Windows owns the surface until outside click or Escape.
        guard !pinned || pin else { return }
        closeTask?.cancel(); closeTask = nil
        let same = self.item?.id == item.id && self.native == native
        if !same {
            generation &+= 1; appearanceTask?.cancel(); appearanceTask = nil
            openingTask?.cancel(); openingTask = nil
            presentation.opening = false; presentation.message = nil
            visibleIDs = []; captures.stop()
        }
        self.item = item; self.anchor = anchor; self.screen = screen; self.native = native
        pinned = pin
        edge = native ? PreviewGeometry.edge(anchor: anchor, screen: screen.frame) : settings.dockPosition
        installMonitors(); update()
        if panel.isVisible || pin { reveal(); return }
        guard appearanceTask == nil else { return }
        let token = generation
        let delay = min(1, max(0, settings.previewHoverDelay))
        if delay == 0 { reveal(); return }
        appearanceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, self.generation == token, self.allowed, self.anchor.contains(NSEvent.mouseLocation) else { self?.dismiss(); return }
            self.appearanceTask = nil; self.reveal()
        }
    }
    private func update() {
        guard allowed, let item, let screen else { return }
        let snapshot = tracker.snapshot
        let app = item.app.flatMap { old in snapshot.apps.first { $0.pid == old.pid } }
            ?? snapshot.apps.first { $0.bundleIdentifier == item.pinnedApp?.bundleIdentifier && item.pinnedApp != nil }
        presentation.app = app
        currentSpaces = SpacePolicy.currentSpaceIDs(snapshot: snapshot, displayID: Self.displayIdentifier(screen), separateSpaces: NSScreen.screensHaveSeparateSpaces)
        if let app {
            presentation.windows = WindowFilter(scope: settings.previewScope, currentSpaceIDs: currentSpaces,
                includeMinimized: settings.previewIncludeMinimized, includeHiddenApps: true, pid: app.pid).apply(to: snapshot.windows)
        } else { presentation.windows = [] }
        presentation.desktopLabels = [:]
        for window in presentation.windows {
            let spaces = SpacePolicy.membership(of: window)
            if Set(spaces).isDisjoint(with: currentSpaces), let space = spaces.sorted().first {
                presentation.desktopLabels[window.id] = desktopNumber?(space).map { "Desktop \($0)" } ?? "Other desktop (Space \(space))"
            }
        }
        let height = min(max(64, settings.previewThumbnailHeight), max(64, screen.visibleFrame.height - 110))
        let width = min(height * 1.6, max(64, screen.visibleFrame.width - 64))
        presentation.thumbnailSize = CGSize(width: width, height: height)
        let count = max(1, presentation.windows.count)
        let contentWidth = presentation.windows.isEmpty ? CGFloat(340) : CGFloat(count) * (width + 16) + CGFloat(count - 1) * 10 + 38
        presentation.size = CGSize(width: min(screen.visibleFrame.width, contentWidth), height: min(screen.visibleFrame.height, presentation.windows.isEmpty ? (presentation.message == nil ? 190 : 280) : height + (presentation.message == nil ? 96 : 170)))
        let frame = PreviewGeometry.frame(size: presentation.size, anchor: anchor, bounds: screen.visibleFrame, edge: edge)
        panel.setFrame(frame, display: panel.isVisible); panel.appearance = Theme.appearance(settings.theme)
        presentation.edge = edge
        presentation.pointerOffset = edge == .bottom ? min(max(anchor.midX - frame.midX, -frame.width / 2 + 24), frame.width / 2 - 24) : min(max(frame.midY - anchor.midY, -frame.height / 2 + 24), frame.height / 2 - 24)
        scheduleCaptures()
    }
    private func reveal() {
        guard allowed, item != nil else { return }
        appearanceTask?.cancel(); appearanceTask = nil
        let visible = panel.isVisible
        panel.orderFrontRegardless()
        if !visible { onVisibilityChanged?(true) }
        scheduleCaptures()
    }
    private func scheduleCaptures() {
        captureUpdateTask?.cancel()
        captureUpdateTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.allowed, self.panel.isVisible else { return }
            self.captures.update(windowIDs: self.visibleIDs.intersection(Set(self.presentation.windows.map(\.id))), interval: self.settings.thumbnailRefreshInterval,
                                 size: self.presentation.thumbnailSize, scale: self.screen?.backingScaleFactor ?? 1)
        }
    }
    private func pointerMoved() {
        guard item != nil, !pinned else { return }
        let point = NSEvent.mouseLocation
        let inside = panel.isVisible ? PreviewGeometry.bridgeContains(point, anchor: anchor, panel: panel.frame, edge: edge) : anchor.contains(point)
        if inside { closeTask?.cancel(); closeTask = nil; return }
        if !panel.isVisible { dismiss(); return }
        guard closeTask == nil else { return }
        closeTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            guard let self else { return }
            self.closeTask = nil
            if !self.pinned, !PreviewGeometry.bridgeContains(NSEvent.mouseLocation, anchor: self.anchor, panel: self.panel.frame, edge: self.edge) { self.dismiss() }
        }
    }
    private func installMonitors() {
        guard localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.dismiss(); return nil }
            self.handleEvent(event); return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            // AppKit delivers global monitors on the main thread.
            self?.handleEvent(event)
        }
    }
    private func handleEvent(_ event: NSEvent) {
        if event.type == .keyDown { if event.keyCode == 53 { dismiss() }; return }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            if !panel.frame.contains(NSEvent.mouseLocation) { dismiss() }
        } else { pointerMoved() }
    }
    private func activate(_ window: TrackedWindow) {
        if settings.previewScope == .currentDesktop, let space = currentSpaces.first(where: { SpacePolicy.membership(of: window).contains($0) }) {
            _ = actions.focus(window, requiringSpace: space)
        } else { actions.focus(window) }
        dismiss()
    }
    private func openWindow() {
        guard allowed, !presentation.opening else { return }
        guard let app = presentation.app else {
            report("Launch this application from the Dock, then use New Window to open a window here."); return
        }
        let space = currentSpaces.sorted().first ?? 0
        let rule = settings.newWindowRule(for: app.bundleIdentifier ?? "")
        pinned = true; presentation.opening = true
        let token = generation
        openingTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.newWindowOpener.open(app: app, onSpace: space, rule: rule)
            guard !Task.isCancelled, self.generation == token else { return }
            self.presentation.opening = false
            switch result {
            case .opened: self.dismiss()
            case .cancelled: break
            case .failed, .unknownSpace:
                self.report("Could not confirm a new \(app.name) window on this desktop. Use the app's File menu to open a window here, then try again.")
            }
        }
    }
    private func report(_ message: String) {
        presentation.message = message; update(); onError?(message)
    }
    private static func displayIdentifier(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    deinit {
        appearanceTask?.cancel(); closeTask?.cancel(); openingTask?.cancel(); captureUpdateTask?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}
