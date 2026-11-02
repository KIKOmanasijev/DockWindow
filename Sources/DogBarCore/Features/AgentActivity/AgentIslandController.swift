import AppKit
import Combine
import SwiftUI

/// The island's window. Borderless, nonactivating and never key, so it cannot take focus from the
/// app being used. It ignores the mouse except while the pointer is over the visible shape.
@MainActor final class AgentIslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Above the menu bar so the shape can sit beside the camera housing.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isMovable = false
    }
    /// Only while the reply field is in use. A nonactivating panel can take the keyboard without
    /// activating DogBar, so the app you were in stays frontmost.
    var allowsKeyboard = false
    override var canBecomeKey: Bool { allowsKeyboard }
    override var canBecomeMain: Bool { false }
    /// The panel overlaps the menu bar on purpose; AppKit would otherwise push it below.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The first click on a button acts immediately; the panel is never activated by it.
final class AgentIslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows the island while Agent Activity is on (or a demo runs), routes the pointer, and owns
/// hover, expansion, display changes, sleep and the scoped ⌘1–⌘9 keys.
@MainActor public final class AgentIslandController {
    private let center: AgentActivityCenter
    private let settings: AppSettings
    private var panel: AgentIslandPanel?
    private var model: AgentIslandModel?
    private var subscriptions = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var intentTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var shortcuts: AgentShortcutTap?
    private var featureEnabled = false
    private var screensAsleep = false
    private var pointerInside = false
    private var mouseDownInside = false
    /// After Escape or the close button, stay collapsed until the pointer leaves once.
    private var suppressUntilExit = false
    private var lastStatuses: [String: AgentStatus] = [:]
    public var onOpenSettings: (() -> Void)?

    /// Hover intent and exit grace (research hypotheses; tune on hardware).
    static let hoverIntent: Duration = .milliseconds(100)
    static let exitGrace: Duration = .milliseconds(240)
    /// Extra room around the open shape that still counts as inside, so small overshoots do not close it.
    static let exitTolerance: CGFloat = 10

    public init(center: AgentActivityCenter, settings: AppSettings) {
        self.center = center
        self.settings = settings
        center.$displayed.sink { [weak self] store in
            DispatchQueue.main.async { self?.storeChanged(store) }
        }.store(in: &subscriptions)
        center.$source.sink { [weak self] _ in DispatchQueue.main.async { self?.reconcile() } }.store(in: &subscriptions)
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.reconcile() }.store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification).sink { [weak self] _ in
            self?.screensAsleep = true; self?.reconcile()
        }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.screensDidWakeNotification).sink { [weak self] _ in
            self?.screensAsleep = false; self?.reconcile()
        }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification).sink { [weak self] _ in
            self?.updateReduceMotion()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            self?.relayout()
        }.store(in: &subscriptions)
    }

    /// Called by the app whenever the opt-in, pause or permissions state changes.
    public func setFeatureEnabled(_ enabled: Bool) {
        featureEnabled = enabled
        center.setEnabled(enabled)
        reconcile()
    }

    private var shouldShow: Bool {
        guard !screensAsleep else { return false }
        if center.source == .demo { return true }
        guard featureEnabled else { return false }
        return settings.agentActivityAlwaysVisible || !center.displayed.sessions.isEmpty
    }

    private func reconcile() {
        if shouldShow { show() } else { hide() }
        updateReduceMotion()
    }

    // MARK: Showing

    private func show() {
        guard let screen = AgentIslandGeometry.preferredScreen() else { hide(); return }
        let geometry = AgentIslandGeometry(screen: screen)
        if panel == nil {
            let model = AgentIslandModel(geometry: geometry)
            model.onCollapse = { [weak self] in self?.collapse(suppress: true) }
            model.onExpand = { [weak self] in self?.expand() }
            model.onOpenSettings = { [weak self] in self?.collapse(suppress: true); self?.onOpenSettings?() }
            model.onPointerActivity = { [weak self] in self?.updatePointer() }
            model.sessionCount = center.displayed.sessions.count
            model.onWantsKeyboard = { [weak self] in self?.takeKeyboard() }
            let panel = AgentIslandPanel()
            let host = AgentIslandHostingView(rootView: AgentIslandView(model: model, center: center))
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel; self.model = model
            lastStatuses = Dictionary(uniqueKeysWithValues: center.displayed.sessions.map { ($0.id, $0.status) })
        }
        guard let panel, let model else { return }
        if model.geometry != geometry { model.geometry = geometry }
        if panel.frame != geometry.panelFrame { panel.setFrame(geometry.panelFrame, display: false) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        installMonitors()
    }

    private func hide() {
        releaseKeyboard()
        removeMonitors()
        intentTask?.cancel(); intentTask = nil
        collapseTask?.cancel(); collapseTask = nil
        stopShortcuts()
        model?.expanded = false
        pointerInside = false
        mouseDownInside = false
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        // Release the SwiftUI tree entirely while hidden: nothing renders or animates.
        panel?.contentView = nil
        panel = nil; model = nil
    }

    private func relayout() {
        guard panel != nil else { return }
        // Collapse instantly across display changes; never fly the shape between screens.
        if let model, model.expanded {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { model.expanded = false }
            stopShortcuts()
        }
        show()
    }

    private func updateReduceMotion() {
        guard let model else { return }
        let reduce = Theme.reducesMotion(settings)
        if model.reduceMotion != reduce { model.reduceMotion = reduce }
    }

    // MARK: Sessions

    private func storeChanged(_ store: AgentActivityStore) {
        reconcile()
        guard let model else { lastStatuses = [:]; return }
        if model.sessionCount != store.sessions.count { model.sessionCount = store.sessions.count }
        // One finite reaction for a meaningful transition of the session the dog represents.
        let focus = model.expanded ? center.selectedID.flatMap { store.session($0) } ?? store.lead : store.lead
        if let focus, let previous = lastStatuses[focus.id], previous != focus.status {
            if focus.status == .needsYou { model.react(.attention) }
            else if focus.status == .finished && focus.turnError == nil { model.react(.finish) }
        }
        lastStatuses = Dictionary(uniqueKeysWithValues: store.sessions.map { ($0.id, $0.status) })
        updatePointer()
    }

    // MARK: Pointer

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: false) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: true) }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }

    private func handle(_ event: NSEvent, local: Bool) {
        switch event.type {
        case .leftMouseDown:
            mouseDownInside = local && event.window === panel
            // A click elsewhere closes the island without waiting for the grace period.
            if !local || event.window !== panel, model?.expanded == true, !pointerInside { collapse(suppress: false) }
        case .leftMouseUp:
            mouseDownInside = false
        default: break
        }
        updatePointer()
    }

    /// The interactive region is exactly the visible shape (plus a small tolerance while open).
    /// Everything else in the panel passes clicks to the app underneath.
    private func interactiveRect() -> CGRect? {
        guard let model else { return nil }
        let frame = model.geometry.shapeFrame(size: model.shapeSize)
        return model.expanded ? frame.insetBy(dx: -Self.exitTolerance, dy: -Self.exitTolerance) : frame
    }

    private func updatePointer() {
        guard let panel, let model, let rect = interactiveRect() else { return }
        let location = NSEvent.mouseLocation
        let visibleShape = model.geometry.shapeFrame(size: model.shapeSize)
        let overShape = visibleShape.contains(location)
        let inside = rect.contains(location)
        let ignores = !(overShape || mouseDownInside)
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
        let wasInside = pointerInside
        pointerInside = inside
        shortcuts?.armed = model.expanded && overShape
        if !inside { suppressUntilExit = false }
        if model.expanded {
            if inside {
                collapseTask?.cancel(); collapseTask = nil
            } else if collapseTask == nil, !mouseDownInside, !model.composing {
                collapseTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.exitGrace)
                    guard !Task.isCancelled, let self else { return }
                    self.collapseTask = nil
                    if !self.pointerInside { self.collapse(suppress: false) }
                }
            }
        } else if inside, !wasInside || intentTask == nil, !suppressUntilExit {
            guard intentTask == nil else { return }
            intentTask = Task { [weak self] in
                try? await Task.sleep(for: Self.hoverIntent)
                guard !Task.isCancelled, let self else { return }
                self.intentTask = nil
                if self.pointerInside, !self.suppressUntilExit { self.expand() }
            }
        } else if !inside {
            intentTask?.cancel(); intentTask = nil
        }
    }

    // MARK: Expansion

    private func expand() {
        guard let model, !model.expanded else { return }
        intentTask?.cancel(); intentTask = nil
        collapseTask?.cancel(); collapseTask = nil
        center.prepareSelection()
        model.expanded = true
        model.react(.expand)
        startShortcuts()
        updatePointer()
    }

    private func collapse(suppress: Bool) {
        guard let model else { return }
        collapseTask?.cancel(); collapseTask = nil
        intentTask?.cancel(); intentTask = nil
        if suppress { suppressUntilExit = pointerInside }
        if model.expanded { model.expanded = false }
        releaseKeyboard()
        stopShortcuts()
        updatePointer()
    }

    private func takeKeyboard() {
        guard let panel, model?.expanded == true else { return }
        panel.allowsKeyboard = true
        if !panel.isKeyWindow { panel.makeKey() }
    }

    private func releaseKeyboard() {
        model?.composing = false
        guard let panel, panel.allowsKeyboard else { return }
        if panel.isKeyWindow { panel.resignKey() }
        panel.allowsKeyboard = false
    }

    private func startShortcuts() {
        guard shortcuts == nil else { return }
        let tap = AgentShortcutTap { [weak self] action in
            guard let self else { return }
            switch action {
            case .select(let slot): self.center.select(slot: slot)
            case .collapse: self.collapse(suppress: true)
            }
        }
        // Without Accessibility the tap cannot be created; the dots and arrows still work.
        if tap.start() { shortcuts = tap; model?.shortcutsAvailable = true } else { model?.shortcutsAvailable = false }
    }

    private func stopShortcuts() {
        shortcuts?.stop(); shortcuts = nil
    }
}
