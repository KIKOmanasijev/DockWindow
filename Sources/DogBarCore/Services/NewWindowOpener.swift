import AppKit
import ApplicationServices

/// Attempts app-specific opening strategies and accepts only a newly tracked window on the requested Space.
@MainActor public final class NewWindowOpener {
    public enum Result { case opened(CGWindowID), failed, cancelled, unknownSpace }
    private let tracker: WindowTracker
    private let actions: WindowActions
    private let queue = DispatchQueue(label: "dev.hristijan.dogbar.newwindow", qos: .userInitiated)
    private var opening = Set<pid_t>()
    private var launching = Set<URL>()
    public init(tracker: WindowTracker) { self.tracker = tracker; actions = WindowActions(tracker: tracker) }
    /// Launches a pin, then accepts only a new window confirmed on the captured display's desktop.
    public func openPinned(bundleURL: URL, onSpace space: UInt64, rule: NewWindowRule? = nil) async -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard tracker.isRunning else { return .failed }
        guard let target = DesktopTarget(spaceID: space, activeSpaceIDs: tracker.snapshot.activeSpaceIDs) else { return .unknownSpace }
        let url = bundleURL.standardizedFileURL
        guard launching.insert(url).inserted else { return .failed }
        defer { launching.remove(url) }
        if let app = tracker.snapshot.apps.first(where: { $0.bundleURL?.standardizedFileURL == url }) {
            return await open(app: app, onSpace: space, rule: rule)
        }
        let lifecycle = tracker.actionCancellation
        let before = Set(tracker.snapshot.windows.map(\.id))
        guard await isCurrent(target, lifecycle: lifecycle), !Task.isCancelled else { return .cancelled }
        guard let running = await launch(url) else { return Task.isCancelled ? .cancelled : .failed }
        guard !Task.isCancelled, await isCurrent(target, lifecycle: lifecycle) else { return .cancelled }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var app: TrackedApp?
        repeat {
            tracker.refresh()
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return .cancelled }
            guard !Task.isCancelled, await isCurrent(target, lifecycle: lifecycle) else { return .cancelled }
            app = tracker.snapshot.apps.first { $0.pid == running.processIdentifier }
            if let window = tracker.snapshot.windows.first(where: {
                $0.pid == running.processIdentifier && !before.contains($0.id) && $0.spaceIDs.contains(space)
            }) {
                let verified = await actions.focusVerified(window, requiringSpace: space)
                if Task.isCancelled || !target.isCurrent(in: tracker.snapshot.activeSpaceIDs) { return .cancelled }
                return verified ? .opened(window.id) : .failed
            }
        } while ProcessInfo.processInfo.systemUptime < deadline
        // A launch-created window with unknown or remote membership is not a reason to create another.
        guard !tracker.snapshot.windows.contains(where: { $0.pid == running.processIdentifier && !before.contains($0.id) }),
              let app else { return .failed }
        guard !Task.isCancelled, await isCurrent(target, lifecycle: lifecycle) else { return .cancelled }
        return await open(app: app, onSpace: space, rule: rule)
    }
    private func isCurrent(_ target: DesktopTarget, lifecycle: OperationCancellation) async -> Bool {
        let current = await Task.detached { SpacesService().read(windowIDs: []).activeSpaceIDs }.value
        return tracker.isRunning && !lifecycle.isCancelled && !Task.isCancelled && target.isCurrent(in: current)
    }
    /// The launch request itself cannot be withdrawn. Bound our wait for its callback.
    private func launch(_ url: URL) async -> NSRunningApplication? {
        let wait = LaunchWait()
        return await withTaskCancellationHandler(operation: {
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                wait.continuation = continuation
                let config = NSWorkspace.OpenConfiguration(); config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
                    Task { @MainActor in wait.finish(app) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { wait.finish(nil) }
            }
        }, onCancel: { Task { @MainActor in wait.finish(nil) } })
    }

    public func open(app: TrackedApp, onSpace space: UInt64, rule: NewWindowRule? = nil) async -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard tracker.isRunning else { return .failed }
        guard let target = DesktopTarget(spaceID: space, activeSpaceIDs: tracker.snapshot.activeSpaceIDs) else { return .unknownSpace }
        guard !Task.isCancelled else { return .cancelled }
        guard opening.insert(app.pid).inserted else { return .failed }
        defer { opening.remove(app.pid) }
        let cancellation = OperationCancellation()
        let lifecycle = tracker.actionCancellation
        return await withTaskCancellationHandler(operation: {
            let before = Set(tracker.snapshot.windows.map(\.id))
            let rule = rule ?? NewWindowRule.defaults.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) ?? NewWindowRule(bundleIdentifier: app.bundleIdentifier ?? "")
            for strategy in NewWindowMenuPolicy.strategies(for: rule) {
                guard !Task.isCancelled, !lifecycle.isCancelled else { return .cancelled }
                let current = await Task.detached { SpacesService().read(windowIDs: []).activeSpaceIDs }.value
                guard target.isCurrent(in: current), !Task.isCancelled, !lifecycle.isCancelled else { return .cancelled }
                NSRunningApplication(processIdentifier: app.pid)?.activate(options: [])
                switch strategy {
                case .menu:
                    _ = await pressNewWindow(pid: app.pid, target: target, cancellation: cancellation, lifecycle: lifecycle, titles: rule.menuTitles.isEmpty ? NewWindowMenuPolicy.defaultTitles : rule.menuTitles)
                case .shortcut:
                    let targetPID = app.pid
                    let displayID = target.displayID, spaceID = target.spaceID
                    await withCheckedContinuation { continuation in
                        queue.async {
                            guard !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(); return }
                            guard SpacesService().read(windowIDs: []).activeSpaceIDs[displayID] == spaceID, !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(); return }
                            for down in [true, false] {
                                let event = CGEvent(keyboardEventSource: nil, virtualKey: rule.shortcut.keyCode, keyDown: down)
                                event?.flags = CGEventFlags(rawValue: rule.shortcut.modifiers.rawValue)
                                event?.postToPid(targetPID)
                            }
                            continuation.resume()
                        }
                    }
                case .reopen:
                    if let url = app.bundleURL {
                        _ = await launch(url)
                    }
                case .automatic: continue
                }
                let deadline = ProcessInfo.processInfo.systemUptime + 1.5
                repeat {
                    tracker.refresh()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled, target.isCurrent(in: tracker.snapshot.activeSpaceIDs), await isCurrent(target, lifecycle: lifecycle) else { return .cancelled }
                    if let window = tracker.snapshot.windows.first(where: { $0.pid == app.pid && !before.contains($0.id) && $0.spaceIDs.contains(space) }) {
                        guard target.isCurrent(in: tracker.snapshot.activeSpaceIDs) else { return .cancelled }
                        let verified = await actions.focusVerified(window, requiringSpace: space)
                        if Task.isCancelled || !target.isCurrent(in: tracker.snapshot.activeSpaceIDs) { return .cancelled }
                        return verified ? .opened(window.id) : .failed
                    }
                } while ProcessInfo.processInfo.systemUptime < deadline
                Log.system.notice("New window strategy \(strategy.rawValue) did not produce a verified window on Space \(space)")
            }
            return .failed
        }, onCancel: { cancellation.cancel() })
    }
    private func pressNewWindow(pid: pid_t, target: DesktopTarget, cancellation: OperationCancellation, lifecycle: OperationCancellation, titles: [String]) async -> Bool {
        let displayID = target.displayID, spaceID = target.spaceID
        return await withCheckedContinuation { continuation in
            queue.async {
                guard !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(returning: false); return }
                let application = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(application, 0.25)
                guard let bar = AXRead.element(application, kAXMenuBarAttribute) else { continuation.resume(returning: false); return }
                var elements: [String: AXUIElement] = [:]
                var count = 0
                let deadline = ProcessInfo.processInfo.systemUptime + 0.5
                func read(_ element: AXUIElement, depth: Int) -> MenuItemDescriptor? {
                    guard !cancellation.isCancelled, !lifecycle.isCancelled, depth <= 4, count < 200, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                    count += 1
                    let id = String(count); elements[id] = element
                    let command = AXRead.value(element, "AXMenuItemCmdChar") as? String
                    let mask = AXRead.value(element, "AXMenuItemCmdModifiers") as? Int ?? 0
                    var modifiers: HotkeyModifiers = []
                    if mask & 8 == 0 { modifiers.insert(.command) }
                    if mask & 1 != 0 { modifiers.insert(.shift) }
                    if mask & 2 != 0 { modifiers.insert(.option) }
                    if mask & 4 != 0 { modifiers.insert(.control) }
                    return MenuItemDescriptor(id: id, title: AXRead.value(element, kAXTitleAttribute) as? String ?? "",
                        isEnabled: AXRead.value(element, kAXEnabledAttribute) as? Bool ?? true,
                        commandCharacter: command, modifiers: modifiers,
                        children: AXRead.children(element).compactMap { read($0, depth: depth + 1) })
                }
                let tree = AXRead.children(bar).compactMap { read($0, depth: 0) }
                guard !cancellation.isCancelled, !lifecycle.isCancelled, let item = NewWindowMenuPolicy.match(in: tree, titles: titles), let element = elements[item.id] else { continuation.resume(returning: false); return }
                guard SpacesService().read(windowIDs: []).activeSpaceIDs[displayID] == spaceID, !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(returning: false); return }
                continuation.resume(returning: AXUIElementPerformAction(element, kAXPressAction as CFString) == .success)
            }
        }
    }
}

@MainActor private final class LaunchWait {
    var continuation: CheckedContinuation<NSRunningApplication?, Never>?
    func finish(_ app: NSRunningApplication?) {
        let pending = continuation; continuation = nil; pending?.resume(returning: app)
    }
}
