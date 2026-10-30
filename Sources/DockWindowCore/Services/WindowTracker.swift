import AppKit
import ApplicationServices
import Combine

/// Main-actor snapshot publisher. AX state and all AX operations live on the worker queue.
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
    private var pending: WindowSnapshot?
    private var scheduledPublish = false
    private var generation = 0
    public init() {}
    deinit { timer?.cancel(); worker.stop() }
    public func start() {
        guard !started else { return }
        started = true
        generation += 1
        let session = generation
        worker.start { [weak self] snapshot in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.started, self.generation == session else { return }
                self.pending = snapshot
                guard !self.scheduledPublish else { return }
                self.scheduledPublish = true
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
                    guard let self, self.generation == session else { return }
                    self.scheduledPublish = false
                    guard let next = self.pending else { return }
                    self.pending = nil
                    let changed = Set(next.windows.map(\.id)) != Set(self.snapshot.windows.map(\.id))
                    self.snapshot = next
                    if changed { self.onWindowInventoryChanged?() }
                }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        let notifications = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification]
        for name in notifications {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
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
        started = false; generation += 1; pending = nil; scheduledPublish = false
        timer?.cancel(); timer = nil
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token); NotificationCenter.default.removeObserver(token) }
        tokens.removeAll(); worker.stop()
    }
    public func refresh() {
        guard started else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }.map {
            TrackedApp(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? "Application",
                       bundleURL: $0.bundleURL, icon: $0.icon ?? NSImage(), isHidden: $0.isHidden, isFrontmost: $0.isActive, badgeLabel: nil)
        }
        worker.refresh(apps: apps)
    }
    /// Executes a window action off-main. The reference never escapes the worker operation.
    internal func perform(windowID: CGWindowID, action: @escaping (AXUIElement) -> Void) {
        worker.perform(windowID: windowID, action: action)
    }
    internal func inspect(_ action: @escaping () -> Void) { worker.queue.async { action() } }
    public func setBadges(_ badges: [String: String]) { worker.setBadges(badges) }
    public func dumpWindows() {
        for app in snapshot.apps { Log.system.info("App \(app.pid) \(app.name) bundle=\(app.bundleIdentifier ?? "unknown")") }
        for window in snapshot.windows { Log.system.info("Window \(window.id) pid=\(window.pid) spaces=\(String(describing: window.spaceIDs)) mru=\(window.lastFocusedAt) title=\(window.title)") }
        Log.system.info("Active spaces: \(String(describing: self.snapshot.activeSpaceIDs))")
    }
}

private final class WindowTrackingWorker {
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
    private var publish: ((WindowSnapshot) -> Void)?
    private var refreshPending = false
    private var badges: [String: String] = [:]
    private var focusedID: CGWindowID?
    private var scanRetries: [pid_t: Int] = [:]
    private var retryScheduled = false
    private var observedPIDs = Set<pid_t>()
    private var activated: [pid_t: (Date, [UInt64])] = [:]
    private let spaceLock = NSLock()
    private var polledIDs: [CGWindowID] = []
    private var session = 0
    func start(publish: @escaping (WindowSnapshot) -> Void) {
        queue.async {
            self.session += 1
            self.publish = publish
            self.hub = AXObserverHub { [weak self] _, notification in
                self?.queue.async { [weak self] in
                    guard let self, self.publish != nil else { return }
                    self.scheduleRefresh()
                }
            }
        }
    }
    func stop() {
        queue.async {
            self.session += 1; self.publish = nil; self.hub?.stop(); self.hub = nil
            self.windows.removeAll(); self.elements.removeAll(); self.apps.removeAll()
            self.cursors.removeAll(); self.lastScan.removeAll(); self.scanRetries.removeAll(); self.activated.removeAll(); self.focusedID = nil; self.observedPIDs.removeAll()
            self.spaceLock.lock(); self.polledIDs = []; self.spaceLock.unlock()
        }
    }
    func setSubroles(_ value: Set<String>) { queue.async { self.subroles = value } }
    func setBadges(_ value: [String: String]) {
        queue.async { self.badges = value; self.emit() }
    }
    func refresh(apps: [TrackedApp]) {
        queue.async {
            for app in apps where app.isFrontmost {
                if !self.apps.contains(where: { $0.pid == app.pid && $0.isFrontmost }) {
                    self.activated[app.pid] = (Date(), Array(self.active.values))
                }
            }
            self.apps = apps; self.scheduleRefresh()
        }
    }
    private func scheduleRefresh() {
        guard !refreshPending, publish != nil else { return }
        refreshPending = true
        queue.asyncAfter(deadline: .now() + .milliseconds(20)) { self.refreshPending = false; self.enumerate() }
    }
    func perform(windowID: CGWindowID, action: @escaping (AXUIElement) -> Void) {
        queue.async { if let element = self.elements[windowID] { action(element) }; self.scheduleRefresh() }
    }
    func pollSpaces() {
        spaceLock.lock(); let ids = polledIDs; spaceLock.unlock()
        let state = SpacesService().read(windowIDs: ids)
        queue.async {
            guard self.publish != nil else { return }
            var changed = self.active != state.activeSpaceIDs
            self.active = state.activeSpaceIDs
            if changed {
                for app in self.apps where app.isFrontmost {
                    self.activated[app.pid] = (self.activated[app.pid]?.0 ?? Date(), Array(state.activeSpaceIDs.values))
                }
            }
            for id in ids {
                guard var window = self.windows[id] else { continue }
                let membership = state.membership[id] ?? []
                // Retain the last known membership while minimized or when a transient query fails.
                if !membership.isEmpty && membership != window.spaceIDs {
                    window.spaceIDs = membership; window.rememberedSpaceIDs = membership; self.windows[id] = window; changed = true
                }
            }
            if changed { self.emit() }
        }
    }
    private func enumerate() {
        guard publish != nil, AXIsProcessTrusted() else { return }
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
            var candidates = raw as? [AXUIElement] ?? []
            for key in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                if let element = AXRead.element(root, key) { candidates.append(element) }
            }
            candidates.append(contentsOf: elements.filter { windows[$0.key]?.pid == app.pid && cg[$0.key] != nil }.map(\.value))
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
                guard roleStatus == .success, roleValue as? String == kAXWindowRole,
                      let record = cg[id], (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                      let subrole = AXRead.value(element, kAXSubroleAttribute) as? String ?? (windows[id] != nil ? kAXStandardWindowSubrole : nil), subroles.contains(subrole),
                      let frame = AXRead.frame(element) ?? windows[id]?.frame, frame.width >= 100, frame.height >= 50 else { continue }
                var window = TrackedWindow(id: id, pid: app.pid, bundleIdentifier: app.bundleIdentifier,
                    title: AXRead.value(element, kAXTitleAttribute) as? String ?? app.name, frame: frame,
                    spaceIDs: windows[id]?.spaceIDs ?? [], isMinimized: AXRead.value(element, kAXMinimizedAttribute) as? Bool ?? windows[id]?.isMinimized ?? false,
                    isAppHidden: app.isHidden, isFullscreen: AXRead.value(element, "AXFullScreen") as? Bool ?? false,
                    lastFocusedAt: windows[id]?.lastFocusedAt ?? .distantPast, rememberedSpaceIDs: windows[id]?.rememberedSpaceIDs ?? windows[id]?.spaceIDs ?? [])
                if app.isFrontmost && id == focused {
                    if focusedID != id || windows[id] == nil { window.lastFocusedAt = Date() }
                    focusedID = id
                }
                nextWindows[id] = window; nextElements[id] = element
            }
            hub?.update(pid: app.pid, windows: nextElements.filter { nextWindows[$0.key]?.pid == app.pid }.map(\.value))
        }
        windows = nextWindows; elements = nextElements
        cursors = cursors.filter { running.contains($0.key) }; lastScan = lastScan.filter { running.contains($0.key) }
        scanRetries = scanRetries.filter { running.contains($0.key) }; activated = activated.filter { running.contains($0.key) }
        spaceLock.lock(); polledIDs = Array(windows.keys); spaceLock.unlock()
        emit()
        spaceQueue.async { self.pollSpaces() }
        if hasGaps && !retryScheduled {
            retryScheduled = true
            let generation = session
            queue.asyncAfter(deadline: .now() + 3) {
                self.retryScheduled = false
                guard self.session == generation, self.publish != nil else { return }
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
        publish?(WindowSnapshot(apps: updatedApps, windows: sorted, activeSpaceIDs: active))
    }
}
