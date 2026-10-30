import AppKit
import ApplicationServices
import Combine

/// Main-actor snapshot publisher. AX inventory and focus reads run on independent worker queues.
@MainActor public final class WindowTracker: ObservableObject {
    @Published public private(set) var snapshot = WindowSnapshot()
    public var allowedSubroles: Set<String> = [kAXStandardWindowSubrole, kAXDialogSubrole] {
        didSet { worker.setSubroles(allowedSubroles); refresh() }
    }
    public var onWindowInventoryChanged: (() -> Void)?
    private let worker = WindowTrackingWorker()
    private var tokens: [NSObjectProtocol] = []
    private var timer: DispatchSourceTimer?
    private var started = false
    internal var isRunning: Bool { started }
    internal private(set) var actionCancellation = OperationCancellation()
    private var eventState = DockFocusSnapshotPolicy()
    private var generation = 0
    public init() {}
    deinit {
        actionCancellation.cancel()
        timer?.cancel(); worker.stop()
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token); NotificationCenter.default.removeObserver(token) }
    }
    public func start() {
        guard !started else { return }
        started = true
        actionCancellation = OperationCancellation()
        generation += 1
        let session = generation
        worker.start(publish: { [weak self] snapshot, revision, activationRevision in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.started, self.generation == session else { return }
                let previous = Set(self.snapshot.windows.map(\.id))
                self.eventState.inventory(snapshot, revision: revision, activationRevision: activationRevision)
                self.snapshot = self.eventState.snapshot
                if previous != Set(self.snapshot.windows.map(\.id)) { self.onWindowInventoryChanged?() }
            }
        }, focus: { [weak self] id, pid, date in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.started, self.generation == session,
                      self.eventState.focused(id: id, pid: pid, at: date) else { return }
                self.snapshot = self.eventState.snapshot
            }
        }, spaces: { [weak self] state, revision, date in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.started, self.generation == session else { return }
                self.eventState.spaces(state.activeSpaceIDs, membership: state.membership, revision: revision, at: date)
                self.snapshot = self.eventState.snapshot
            }
        })
        let center = NSWorkspace.shared.notificationCenter
        let notifications = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification]
        for name in notifications {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.started else { return }
                    if name == NSWorkspace.didActivateApplicationNotification,
                       let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        let date = Date()
                        // Workspace already supplies the app. Publish before collecting apps or doing any AX work.
                        let tracked = self.snapshot.apps.first { $0.pid == app.processIdentifier }
                            ?? TrackedApp(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                                          name: app.localizedName ?? "Application", bundleURL: app.bundleURL)
                        self.eventState.activate(tracked, at: date, includeInInventory: app.activationPolicy == .regular)
                        self.snapshot = self.eventState.snapshot
                        self.worker.requestFocus(pid: app.processIdentifier, at: date)
                    }
                    if name == NSWorkspace.activeSpaceDidChangeNotification || name == NSWorkspace.didActivateApplicationNotification {
                        self.worker.requestSpaces()
                    }
                    self.refresh()
                }
            })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        let timer = DispatchSource.makeTimerSource(queue: worker.spaceQueue)
        timer.schedule(deadline: .now() + 1.5, repeating: 1.5, leeway: .milliseconds(150))
        timer.setEventHandler { [weak worker] in worker?.pollSpaces() }
        timer.resume()
        self.timer = timer
        refresh()
    }
    public func stop() {
        actionCancellation.cancel()
        started = false; generation += 1; eventState = DockFocusSnapshotPolicy()
        timer?.cancel(); timer = nil
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token); NotificationCenter.default.removeObserver(token) }
        tokens.removeAll(); worker.stop()
    }
    public func refresh() {
        guard started else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map {
            TrackedApp(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? "Application",
                       bundleURL: $0.bundleURL, icon: $0.icon ?? NSImage(), isHidden: $0.isHidden, isFrontmost: $0.isActive, badgeLabel: nil)
        }
        worker.refresh(apps: apps, activationRevision: eventState.activationRevision)
    }
    /// Executes a window action off-main. The reference never escapes the worker operation.
    internal func perform(windowID: CGWindowID, ifMissing: @escaping () -> Void = {}, action: @escaping (AXUIElement) -> Void) {
        guard started else { ifMissing(); return }
        let cancellation = actionCancellation
        worker.perform(windowID: windowID, ifMissing: ifMissing) { element in
            guard !cancellation.isCancelled else { ifMissing(); return }
            action(element)
        }
    }
    internal func inspect(_ action: @escaping () -> Void) { worker.queue.async { action() } }
    public func setBadges(_ badges: [String: String]) { worker.setBadges(badges) }
    public func dumpWindows() {
        for app in snapshot.apps { Log.system.info("App \(app.pid) \(app.name) bundle=\(app.bundleIdentifier ?? "unknown")") }
        for window in snapshot.windows { Log.system.info("Window \(window.id) pid=\(window.pid) spaces=\(String(describing: window.spaceIDs)) mru=\(window.lastFocusedAt) title=\(window.title)") }
        Log.system.info("Active spaces: \(String(describing: self.snapshot.activeSpaceIDs))")
    }
}

// Mutable inventory stays on queue. Membership query input is protected by spaceLock.
private final class WindowTrackingWorker: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.dockwindow.ax", qos: .userInitiated)
    let spaceQueue = DispatchQueue(label: "com.dockwindow.spaces", qos: .utility)
    private var hub: AXObserverHub?
    private var apps: [TrackedApp] = []
    private var windows: [CGWindowID: TrackedWindow] = [:]
    private var elements: [CGWindowID: AXUIElement] = [:]
    private var cursors: [pid_t: UInt64] = [:]
    private var lastScan: [pid_t: Date] = [:]
    private var subroles: Set<String> = [kAXStandardWindowSubrole, kAXDialogSubrole]
    private var active: [String: UInt64] = [:]
    private var publish: ((WindowSnapshot, UInt64, UInt64) -> Void)?
    private var publishFocus: ((CGWindowID, pid_t, Date) -> Void)?
    private var publishSpaces: ((SpacesService.State, UInt64, Date) -> Void)?
    private let topologyQueue = DispatchQueue(label: "com.dockwindow.topology", qos: .userInitiated)
    private var spaceDate = Date.distantPast
    private let focusQueue = DispatchQueue(label: "com.dockwindow.focus", qos: .userInteractive)
    private let focusLock = NSLock()
    private var focusRequest: (pid: pid_t, date: Date)?
    private var focusScheduled = false
    private var focusSession = 0
    private var refreshPending = false
    private var badges: [String: String] = [:]
    private var focusedID: CGWindowID?
    private var scanRetries: [pid_t: Int] = [:]
    private var retryScheduled = false
    private var observedPIDs = Set<pid_t>()
    private var activated: [pid_t: (Date, [UInt64])] = [:]
    private let spaceLock = NSLock()
    private var polledIDs: [CGWindowID] = []
    private var membershipQueued = false
    private var topologyQueued = false
    private var session = 0
    private var pollingSession = 0
    private var inventoryRevision: UInt64 = 0
    private var activationRevision: UInt64 = 0
    private var polledRevision: UInt64 = 0
    func start(publish: @escaping (WindowSnapshot, UInt64, UInt64) -> Void,
               focus: @escaping (CGWindowID, pid_t, Date) -> Void,
               spaces: @escaping (SpacesService.State, UInt64, Date) -> Void) {
        queue.async {
            self.session += 1
            self.spaceLock.lock(); self.pollingSession = self.session; self.spaceLock.unlock()
            self.publish = publish
            self.focusLock.lock(); self.publishFocus = focus; self.focusSession = self.session; self.focusLock.unlock()
            self.spaceLock.lock(); self.publishSpaces = spaces; self.spaceLock.unlock()
            let generation = self.session
            self.hub = AXObserverHub { [weak self] pid, notification in
                if [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXApplicationActivatedNotification].contains(notification) {
                    self?.requestFocus(pid: pid, at: Date())
                    return
                }
                self?.queue.async { [weak self] in
                    guard let self, self.publish != nil, self.session == generation else { return }
                    self.scheduleRefresh()
                }
            }
        }
    }
    func stop() {
        queue.async {
            self.focusLock.lock(); self.publishFocus = nil; self.focusRequest = nil; self.focusSession += 1; self.focusLock.unlock()
            self.session += 1; self.publish = nil; self.hub?.stop(); self.hub = nil
            self.windows.removeAll(); self.elements.removeAll(); self.apps.removeAll()
            self.cursors.removeAll(); self.lastScan.removeAll(); self.scanRetries.removeAll(); self.activated.removeAll(); self.focusedID = nil; self.observedPIDs.removeAll()
            self.refreshPending = false; self.retryScheduled = false; self.active = [:]; self.spaceDate = .distantPast
            self.spaceLock.lock(); self.pollingSession = self.session; self.polledIDs = []; self.publishSpaces = nil; self.spaceLock.unlock()
        }
    }
    func setSubroles(_ value: Set<String>) { queue.async { self.subroles = value } }
    func setBadges(_ value: [String: String]) {
        queue.async { self.badges = value; self.emit() }
    }
    func refresh(apps: [TrackedApp], activationRevision: UInt64) {
        let requested = Date()
        queue.async {
            for app in apps where app.isFrontmost {
                if !self.apps.contains(where: { $0.pid == app.pid && $0.isFrontmost }) {
                    self.activated[app.pid] = (requested, Array(self.active.values))
                }
            }
            self.apps = apps; self.activationRevision = activationRevision; self.scheduleRefresh()
        }
    }
    private func scheduleRefresh() {
        guard !refreshPending, publish != nil else { return }
        refreshPending = true
        let generation = session
        queue.asyncAfter(deadline: .now() + .milliseconds(20)) {
            guard self.session == generation else { return }
            self.refreshPending = false; self.enumerate()
        }
    }
    func perform(windowID: CGWindowID, ifMissing: @escaping () -> Void, action: @escaping (AXUIElement) -> Void) {
        queue.async { if let element = self.elements[windowID] { action(element) } else { ifMissing() }; self.scheduleRefresh() }
    }
    /// Coalesced focus-only reads never queue behind full inventory or remote discovery.
    func requestFocus(pid: pid_t, at date: Date) {
        focusLock.lock()
        focusRequest = (pid, date)
        guard !focusScheduled else { focusLock.unlock(); return }
        focusScheduled = true
        focusLock.unlock()
        focusQueue.async { self.drainFocus() }
    }
    private func drainFocus() {
        focusLock.lock()
        let request = focusRequest; focusRequest = nil
        let generation = focusSession
        focusLock.unlock()
        if let request {
            let root = AXUIElementCreateApplication(request.pid)
            AXUIElementSetMessagingTimeout(root, 0.05)
            if let element = AXRead.element(root, kAXFocusedWindowAttribute) {
                AXUIElementSetMessagingTimeout(element, 0.05)
                if let id = AXPrivate.shared.windowID(of: element) {
                    focusLock.lock()
                    let callback = generation == focusSession ? publishFocus : nil
                    focusLock.unlock()
                    callback?(id, request.pid, request.date)
                    queue.async {
                        guard self.publish != nil, self.session == generation else { return }
                        guard self.apps.contains(where: { $0.pid == request.pid && $0.isFrontmost }) else { return }
                        if var window = self.windows[id], window.pid == request.pid {
                            window.lastFocusedAt = max(window.lastFocusedAt, request.date)
                            self.windows[id] = window; self.focusedID = id
                        } else { self.scheduleRefresh() }
                    }
                }
            }
        }
        focusLock.lock()
        let again = focusRequest != nil
        if !again { focusScheduled = false }
        focusLock.unlock()
        if again { focusQueue.async { self.drainFocus() } }
    }
    /// Event topology reads bypass both AX inventory and batched membership work.
    func requestSpaces() {
        spaceLock.lock()
        let enqueueTopology = !topologyQueued
        topologyQueued = true
        spaceLock.unlock()
        if enqueueTopology {
            topologyQueue.async {
                self.spaceLock.lock()
                self.topologyQueued = false
                let callback = self.publishSpaces; let revision = self.polledRevision
                self.spaceLock.unlock()
                let date = Date()
                let state = SpacesService().read(windowIDs: [])
                callback?(state, revision, date)
            }
        }
        requestMembership()
    }
    private func requestMembership() {
        spaceLock.lock()
        guard !membershipQueued else { spaceLock.unlock(); return }
        membershipQueued = true
        spaceLock.unlock()
        spaceQueue.async {
            self.spaceLock.lock(); self.membershipQueued = false; self.spaceLock.unlock()
            self.pollSpaces()
        }
    }
    func pollSpaces() {
        spaceLock.lock(); let ids = polledIDs; let generation = pollingSession; let revision = polledRevision; let callback = publishSpaces; spaceLock.unlock()
        // Publish topology first, before per-window membership discovery, and bypass the AX queue.
        let date = Date()
        let topology = SpacesService().read(windowIDs: [])
        callback?(topology, revision, date)
        let state = SpacesService().read(windowIDs: ids)
        callback?(state, revision, date)
        queue.async {
            guard self.publish != nil, self.session == generation, date >= self.spaceDate else { return }
            self.spaceDate = date
            var changed = self.active != state.activeSpaceIDs
            self.active = state.activeSpaceIDs
            if changed {
                for app in self.apps where app.isFrontmost {
                    self.activated[app.pid] = (self.activated[app.pid]?.0 ?? Date(), Array(state.activeSpaceIDs.values))
                }
            }
            for id in ids where self.inventoryRevision == revision {
                guard var window = self.windows[id] else { continue }
                let membership = state.membership[id] ?? []
                // Retain the last known membership while minimized or when a transient query fails.
                if !window.isMinimized && !membership.isEmpty && membership != window.spaceIDs {
                    window.spaceIDs = membership; window.rememberedSpaceIDs = membership; self.windows[id] = window; changed = true
                }
            }
            if changed { self.emit() }
        }
    }
    private func enumerate() {
        guard publish != nil, AXIsProcessTrusted() else { return }
        let scanStarted = Date()
        let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        var cg: [CGWindowID: [String: Any]] = [:]
        for item in info {
            if let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value { cg[id] = item }
        }
        let running = Set(apps.map(\.pid))
        for pid in observedPIDs.subtracting(running) { hub?.remove(pid: pid) }
        observedPIDs = running
        let scanDeadline = ProcessInfo.processInfo.systemUptime + 0.25
        var hasGaps = false
        var nextWindows: [CGWindowID: TrackedWindow] = [:]
        var nextElements: [CGWindowID: AXUIElement] = [:]
        for app in apps {
            let root = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(root, 0.25)
            var raw: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &raw)
            if status == .cannotComplete {
                for (id, value) in windows where value.pid == app.pid { nextWindows[id] = value; nextElements[id] = elements[id] }
                continue
            }
            var candidates = AXRead.elements(raw)
            for key in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                if let element = AXRead.element(root, key) { candidates.append(element) }
            }
            candidates.append(contentsOf: elements.filter { windows[$0.key]?.pid == app.pid && (cg[$0.key] != nil || windows[$0.key]?.isMinimized == true) }.map(\.value))
            let known = Set(candidates.compactMap { AXPrivate.shared.windowID(of: $0) })
            let missing = Set(cg.compactMap { id, item -> CGWindowID? in
                guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.pid,
                      (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0 else { return nil }
                return id
            }).subtracting(known)
            if !missing.isEmpty, ProcessInfo.processInfo.systemUptime < scanDeadline, Date().timeIntervalSince(lastScan[app.pid] ?? .distantPast) >= 3 {
                candidates += discover(pid: app.pid, wanted: missing)
                lastScan[app.pid] = Date()
                scanRetries[app.pid, default: 0] += 1
            }
            if !missing.isEmpty && scanRetries[app.pid, default: 0] < 16 { hasGaps = true }
            let focused = AXRead.element(root, kAXFocusedWindowAttribute).flatMap { AXPrivate.shared.windowID(of: $0) }
            for element in candidates {
                AXUIElementSetMessagingTimeout(element, 0.25)
                guard let id = AXPrivate.shared.windowID(of: element), nextWindows[id] == nil else { continue }
                var roleValue: CFTypeRef?
                let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
                if roleStatus == .cannotComplete, let previous = windows[id], cg[id] != nil {
                    nextWindows[id] = previous; nextElements[id] = element; continue
                }
                let minimized = AXRead.value(element, kAXMinimizedAttribute) as? Bool ?? windows[id]?.isMinimized ?? false
                // A validated AX root may survive being removed from the server's minimized inventory.
                let previousRecord: [String: Any]? = minimized && windows[id] != nil ? [kCGWindowLayer as String: 0, kCGWindowAlpha as String: 1] : nil
                guard roleStatus == .success, roleValue as? String == kAXWindowRole,
                      let record = cg[id] ?? previousRecord, (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      ((record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0 || minimized),
                      let subrole = AXRead.value(element, kAXSubroleAttribute) as? String ?? (windows[id] != nil ? kAXStandardWindowSubrole : nil), subroles.contains(subrole),
                      let frame = AXRead.frame(element) ?? windows[id]?.frame, frame.width >= 100, frame.height >= 50 else { continue }
                var window = TrackedWindow(id: id, pid: app.pid, bundleIdentifier: app.bundleIdentifier,
                    title: AXRead.value(element, kAXTitleAttribute) as? String ?? app.name, frame: frame,
                    spaceIDs: windows[id]?.spaceIDs ?? [], isMinimized: minimized,
                    isAppHidden: app.isHidden, isFullscreen: AXRead.value(element, "AXFullScreen") as? Bool ?? false,
                    lastFocusedAt: windows[id]?.lastFocusedAt ?? .distantPast, rememberedSpaceIDs: windows[id]?.rememberedSpaceIDs ?? windows[id]?.spaceIDs ?? [])
                if app.isFrontmost && id == focused {
                    if focusedID != id || windows[id] == nil { window.lastFocusedAt = scanStarted }
                    focusedID = id
                }
                nextWindows[id] = window; nextElements[id] = element
            }
            hub?.update(pid: app.pid, windows: nextElements.filter { nextWindows[$0.key]?.pid == app.pid }.map(\.value))
        }
        windows = nextWindows; elements = nextElements
        cursors = cursors.filter { running.contains($0.key) }; lastScan = lastScan.filter { running.contains($0.key) }
        scanRetries = scanRetries.filter { running.contains($0.key) }; activated = activated.filter { running.contains($0.key) }
        inventoryRevision &+= 1
        spaceLock.lock(); polledIDs = Array(windows.keys); polledRevision = inventoryRevision; spaceLock.unlock()
        emit()
        requestMembership()
        if hasGaps && !retryScheduled {
            retryScheduled = true
            let generation = session
            queue.asyncAfter(deadline: .now() + 3) {
                guard self.session == generation, self.publish != nil else { return }
                self.retryScheduled = false
                self.scheduleRefresh()
            }
        }
    }
    private func discover(pid: pid_t, wanted: Set<CGWindowID>) -> [AXUIElement] {
        var cursor = cursors[pid] ?? 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.04
        var remaining = wanted
        var found: [AXUIElement] = []
        var count = 0
        while !remaining.isEmpty && count < 256 && ProcessInfo.processInfo.systemUptime < deadline {
            defer { cursor &+= 1; count += 1 }
            guard let element = AXPrivate.shared.element(pid: pid, elementID: cursor) else { continue }
            AXUIElementSetMessagingTimeout(element, 0.01)
            guard let id = AXPrivate.shared.windowID(of: element), remaining.contains(id),
                  ProcessInfo.processInfo.systemUptime < deadline,
                  AXRead.value(element, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
            found.append(element); remaining.remove(id)
        }
        cursors[pid] = cursor
        return found
    }
    private func emit() {
        let sorted = windows.values.sorted { $0.lastFocusedAt == $1.lastFocusedAt ? $0.id < $1.id : $0.lastFocusedAt > $1.lastFocusedAt }
        var updatedApps = apps
        for index in updatedApps.indices {
            updatedApps[index].badgeLabel = badges[updatedApps[index].bundleIdentifier ?? ""]
            if let activation = activated[updatedApps[index].pid] {
                updatedApps[index].lastActivatedAt = activation.0
                updatedApps[index].lastActiveSpaceIDs = activation.1
            }
        }
        publish?(WindowSnapshot(apps: updatedApps, windows: sorted, activeSpaceIDs: active), inventoryRevision, activationRevision)
    }
}
