import AppKit
import ApplicationServices

/// Window operations use retained tracker references off-main; application lifecycle runs on main.
@MainActor public final class WindowActions {
    private let tracker: WindowTracker
    public init(tracker: WindowTracker) { self.tracker = tracker }
    public func focus(_ window: TrackedWindow) {
        tracker.perform(windowID: window.id) { element in
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if window.isAppHidden { NSRunningApplication(processIdentifier: window.pid)?.unhide() }
                self.tracker.perform(windowID: window.id) { element in
                    let focused = ProcessFocus.shared.focus(pid: window.pid, windowID: window.id)
                    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                    if !focused {
                        DispatchQueue.main.async {
                            NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
                        }
                        Log.system.notice("Private focus unavailable or failed for window \(window.id); using activation fallback")
                    }
                }
            }
        }
        Task { try? await Task.sleep(nanoseconds: 200_000_000); tracker.refresh() }
    }
    /// Refuses an unconfirmed current-Space target. False also covers missing Space data.
    @discardableResult public func focus(_ window: TrackedWindow, requiringSpace space: UInt64) -> Bool {
        guard space != 0, window.spaceIDs.contains(space) || window.isMinimized && window.rememberedSpaceIDs.contains(space) else { return false }
        focus(window); return true
    }
    /// Verifies AX focused-window identity after the focus attempt. This is evidence, not a Space-switch guarantee.
    public func focusVerified(_ window: TrackedWindow, requiringSpace space: UInt64? = nil) async -> Bool {
        if let space {
            let membership: [UInt64]? = await Task.detached { SkyLight.shared.spaces(containing: [window.id]) }.value
            guard membership?.contains(space) == true || window.isMinimized && window.rememberedSpaceIDs.contains(space) else { return false }
        }
        focus(window)
        try? await Task.sleep(nanoseconds: 150_000_000)
        let isFocused: Bool = await withCheckedContinuation { continuation in
            tracker.inspect {
                let root = AXUIElementCreateApplication(window.pid)
                AXUIElementSetMessagingTimeout(root, 0.25)
                let focused = AXRead.element(root, kAXFocusedWindowAttribute).flatMap { AXPrivate.shared.windowID(of: $0) }
                continuation.resume(returning: focused == window.id)
            }
        }
        guard isFocused else { return false }
        if let space {
            let state = await Task.detached { SpacesService().read(windowIDs: [window.id]) }.value
            return state.activeSpaceIDs.values.contains(space) && state.membership[window.id]?.contains(space) == true
        }
        return true
    }
    public func focus(windowID: CGWindowID) { if let window = tracker.snapshot.windows.first(where: { $0.id == windowID }) { focus(window) } }
    public func close(_ window: TrackedWindow) {
        tracker.perform(windowID: window.id) { element in
            if let button = AXRead.element(element, kAXCloseButtonAttribute) { AXUIElementPerformAction(button, kAXPressAction as CFString) }
        }
    }
    public func minimize(_ window: TrackedWindow) {
        tracker.perform(windowID: window.id) { AXUIElementSetAttributeValue($0, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
    }
    public func zoom(_ window: TrackedWindow) {
        tracker.perform(windowID: window.id) {
            let value = AXRead.value($0, "AXFullScreen") as? Bool ?? false
            AXUIElementSetAttributeValue($0, "AXFullScreen" as CFString, value ? kCFBooleanFalse : kCFBooleanTrue)
        }
    }
    public func hide(pid: pid_t) { NSRunningApplication(processIdentifier: pid)?.hide(); tracker.refresh() }
    public func quit(pid: pid_t, force: Bool = false) {
        if force { NSRunningApplication(processIdentifier: pid)?.forceTerminate() } else { NSRunningApplication(processIdentifier: pid)?.terminate() }
    }
    public func hide(_ window: TrackedWindow) { hide(pid: window.pid) }
    public func quit(_ window: TrackedWindow) { quit(pid: window.pid) }
}
