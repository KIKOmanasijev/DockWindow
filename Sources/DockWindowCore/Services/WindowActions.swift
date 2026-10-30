import AppKit
import ApplicationServices

/// Window operations use retained tracker references off-main; application lifecycle runs on main.
@MainActor public final class WindowActions {
    private let tracker: WindowTracker
    public init(tracker: WindowTracker) { self.tracker = tracker }
    public func focus(_ window: TrackedWindow) {
        let lifecycle = tracker.actionCancellation
        tracker.perform(windowID: window.id) { element in
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            DispatchQueue.main.async { [weak self] in
                guard let self, !lifecycle.isCancelled else { return }
                if window.isAppHidden { NSRunningApplication(processIdentifier: window.pid)?.unhide() }
                self.tracker.perform(windowID: window.id) { element in
                    let focused = ProcessFocus.shared.focus(pid: window.pid, windowID: window.id)
                    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                    if !focused {
                        DispatchQueue.main.async {
                            guard !lifecycle.isCancelled else { return }
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
        let cancellation = OperationCancellation()
        let lifecycle = tracker.actionCancellation
        return await withTaskCancellationHandler(operation: {
            guard !Task.isCancelled, !lifecycle.isCancelled else { return false }
            let target: DesktopTarget?
            if let space {
                guard let requested = DesktopTarget(spaceID: space, activeSpaceIDs: tracker.snapshot.activeSpaceIDs) else { return false }
                let state = await Task.detached { SpacesService().read(windowIDs: [window.id]) }.value
                guard !Task.isCancelled, requested.isCurrent(in: state.activeSpaceIDs),
                      state.membership[window.id]?.contains(space) == true || window.isMinimized && window.rememberedSpaceIDs.contains(space) else { return false }
                target = requested
            } else { target = nil }
            guard !Task.isCancelled, !lifecycle.isCancelled else { return false }
            let restored: Bool = await withCheckedContinuation { continuation in
                tracker.perform(windowID: window.id, ifMissing: { continuation.resume(returning: false) }) { element in
                    guard !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(returning: false); return }
                    if let target, !target.isCurrent(in: SpacesService().read(windowIDs: []).activeSpaceIDs) {
                        continuation.resume(returning: false); return
                    }
                    guard !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(returning: false); return }
                    AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    continuation.resume(returning: true)
                }
            }
            guard restored, !Task.isCancelled, !lifecycle.isCancelled else { return false }
            if let target {
                let state = await Task.detached { SpacesService().read(windowIDs: []).activeSpaceIDs }.value
                guard !Task.isCancelled, target.isCurrent(in: state) else { return false }
            }
            guard !Task.isCancelled, !lifecycle.isCancelled else { return false }
            if window.isAppHidden { NSRunningApplication(processIdentifier: window.pid)?.unhide() }
            let focused: Bool? = await withCheckedContinuation { continuation in
                tracker.perform(windowID: window.id, ifMissing: { continuation.resume(returning: nil) }) { element in
                    guard !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(returning: false); return }
                    if let target, !target.isCurrent(in: SpacesService().read(windowIDs: []).activeSpaceIDs) {
                        continuation.resume(returning: false); return
                    }
                    guard !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(returning: false); return }
                    let result = ProcessFocus.shared.focus(pid: window.pid, windowID: window.id, isCancelled: { cancellation.isCancelled || lifecycle.isCancelled })
                    if !cancellation.isCancelled && !lifecycle.isCancelled {
                        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    }
                    if !cancellation.isCancelled && !lifecycle.isCancelled {
                        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                    }
                    continuation.resume(returning: result)
                }
            }
            guard let focused, !Task.isCancelled, !lifecycle.isCancelled else { return false }
            if !focused {
                if let target {
                    let state = await Task.detached { SpacesService().read(windowIDs: []).activeSpaceIDs }.value
                    guard !Task.isCancelled, target.isCurrent(in: state) else { return false }
                }
                guard !Task.isCancelled, !lifecycle.isCancelled else { return false }
                NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            }
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return false }
            guard !Task.isCancelled, !lifecycle.isCancelled else { return false }
            let isFocused: Bool = await withCheckedContinuation { continuation in
                tracker.inspect {
                    guard !cancellation.isCancelled, !lifecycle.isCancelled else { continuation.resume(returning: false); return }
                    let root = AXUIElementCreateApplication(window.pid)
                    AXUIElementSetMessagingTimeout(root, 0.25)
                    let focused = AXRead.element(root, kAXFocusedWindowAttribute).flatMap { AXPrivate.shared.windowID(of: $0) }
                    continuation.resume(returning: focused == window.id)
                }
            }
            guard isFocused, !Task.isCancelled, !lifecycle.isCancelled else { return false }
            if let target {
                let state = await Task.detached { SpacesService().read(windowIDs: [window.id]) }.value
                return !Task.isCancelled && !lifecycle.isCancelled && target.isCurrent(in: state.activeSpaceIDs) && state.membership[window.id]?.contains(target.spaceID) == true
            }
            return !Task.isCancelled && !lifecycle.isCancelled
        }, onCancel: { cancellation.cancel() })
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
    public func hide(pid: pid_t, completion: ((Bool) -> Void)? = nil) {
        guard pid > 0, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            completion?(false); return
        }
        let lifecycle = tracker.actionCancellation
        Task { [weak self] in
            let hidden = await ApplicationHideOperation.run(
                isHidden: { app.isHidden }, isTerminated: { app.isTerminated },
                isCancelled: { lifecycle.isCancelled }, requestHide: { app.hide() },
                setAXHidden: {
                    await Task.detached(priority: .userInitiated) {
                        guard !lifecycle.isCancelled else { return false }
                        let element = AXUIElementCreateApplication(pid)
                        AXUIElementSetMessagingTimeout(element, 0.25)
                        return AXUIElementSetAttributeValue(element, kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success
                    }.value
                })
            guard !lifecycle.isCancelled else { return }
            self?.tracker.refresh()
            if !hidden { Log.system.error("Could not hide application pid \(pid)") }
            completion?(hidden)
        }
    }
    public func quit(pid: pid_t, force: Bool = false) {
        if force { NSRunningApplication(processIdentifier: pid)?.forceTerminate() } else { NSRunningApplication(processIdentifier: pid)?.terminate() }
    }
    public func hide(_ window: TrackedWindow) { hide(pid: window.pid) }
    public func quit(_ window: TrackedWindow) { quit(pid: window.pid) }
}
