import AppKit
import ApplicationServices

/// Attempts app-specific opening strategies and accepts only a newly tracked window on the requested Space.
@MainActor public final class NewWindowOpener {
    public enum Result { case opened(CGWindowID), failed, cancelled, unknownSpace }
    private let tracker: WindowTracker
    private let actions: WindowActions
    private let queue = DispatchQueue(label: "com.dockwindow.newwindow", qos: .userInitiated)
    private var opening = Set<pid_t>()
    public init(tracker: WindowTracker) { self.tracker = tracker; actions = WindowActions(tracker: tracker) }
    public func open(app: TrackedApp, onSpace space: UInt64, rule: NewWindowRule? = nil) async -> Result {
        guard let target = DesktopTarget(spaceID: space, activeSpaceIDs: tracker.snapshot.activeSpaceIDs) else { return .unknownSpace }
        guard opening.insert(app.pid).inserted else { return .failed }
        defer { opening.remove(app.pid) }
        let before = Set(tracker.snapshot.windows.map(\.id))
        let rule = rule ?? NewWindowRule.defaults.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) ?? NewWindowRule(bundleIdentifier: app.bundleIdentifier ?? "")
        for strategy in NewWindowMenuPolicy.strategies(for: rule) {
            guard !Task.isCancelled else { return .cancelled }
            let current = await Task.detached { SpacesService().read(windowIDs: []).activeSpaceIDs }.value
            guard target.isCurrent(in: current), !Task.isCancelled else { return .cancelled }
            NSRunningApplication(processIdentifier: app.pid)?.activate(options: [])
            switch strategy {
            case .menu:
                _ = await pressNewWindow(pid: app.pid, titles: rule.menuTitles.isEmpty ? NewWindowMenuPolicy.defaultTitles : rule.menuTitles)
            case .shortcut:
                let targetPID = app.pid
                await withCheckedContinuation { continuation in
                    queue.async {
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
                    let config = NSWorkspace.OpenConfiguration(); config.activates = true
                    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
                }
            case .automatic: continue
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 1.5
            repeat {
                tracker.refresh()
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled || !target.isCurrent(in: tracker.snapshot.activeSpaceIDs) { return .cancelled }
                if let window = tracker.snapshot.windows.first(where: { $0.pid == app.pid && !before.contains($0.id) && $0.spaceIDs.contains(space) }) {
                    guard target.isCurrent(in: tracker.snapshot.activeSpaceIDs), await actions.focusVerified(window, requiringSpace: space) else { return .failed }
                    return .opened(window.id)
                }
            } while ProcessInfo.processInfo.systemUptime < deadline
            Log.system.notice("New window strategy \(strategy.rawValue) did not produce a verified window on Space \(space)")
        }
        return .failed
    }
    private func pressNewWindow(pid: pid_t, titles: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                let application = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(application, 0.25)
                guard let bar = AXRead.element(application, kAXMenuBarAttribute) else { continuation.resume(returning: false); return }
                var elements: [String: AXUIElement] = [:]
                var count = 0
                let deadline = ProcessInfo.processInfo.systemUptime + 0.5
                func read(_ element: AXUIElement, depth: Int) -> MenuItemDescriptor? {
                    guard depth <= 4, count < 200, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
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
                guard let item = NewWindowMenuPolicy.match(in: tree, titles: titles), let element = elements[item.id] else { continuation.resume(returning: false); return }
                continuation.resume(returning: AXUIElementPerformAction(element, kAXPressAction as CFString) == .success)
            }
        }
    }
}
