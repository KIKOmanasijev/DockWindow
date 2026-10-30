import ApplicationServices
import Foundation

/// Owns all AXObservers on a dedicated thread and run loop. Callbacks only enqueue tracker work.
public final class AXObserverHub {
    private final class Context {
        let handler: (pid_t, String) -> Void
        init(_ handler: @escaping (pid_t, String) -> Void) { self.handler = handler }
    }
    private struct Registration {
        let observer: AXObserver
        let application: AXUIElement
        var windows: [AXUIElement]
    }
    private let context: Context
    private let lock = NSLock()
    private var loop: CFRunLoop?
    private var stopped = false
    private var registrations: [pid_t: Registration] = [:]
    private var pending: [() -> Void] = []
    private static let appEvents = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification, kAXApplicationHiddenNotification, kAXApplicationShownNotification,
        kAXApplicationActivatedNotification]
    private static let windowEvents = [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification, kAXWindowResizedNotification]
    public init(handler: @escaping (pid_t, String) -> Void) {
        context = Context(handler)
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "DockWindow AX observers"
        thread.qualityOfService = .utility
        thread.start()
    }
    private func run() {
        let runLoop = CFRunLoopGetCurrent()
        let keepAlive = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 3600, 3600, 0, 0) { _ in }
        if let timer = keepAlive { CFRunLoopAddTimer(runLoop, timer, .defaultMode) }
        lock.lock()
        if stopped { lock.unlock(); return }
        loop = runLoop
        let work = pending
        pending.removeAll()
        lock.unlock()
        work.forEach { $0() }
        CFRunLoopRun()
        for registration in registrations.values { CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(registration.observer), .defaultMode) }
        registrations.removeAll()
        lock.lock(); loop = nil; lock.unlock()
    }
    private func enqueue(_ work: @escaping () -> Void) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        guard let loop else { pending.append(work); lock.unlock(); return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(loop)
        lock.unlock()
    }
    public func update(pid: pid_t, windows: [AXUIElement]) {
        enqueue { [weak self] in
            guard let self else { return }
            if self.registrations[pid] == nil {
                var observer: AXObserver?
                let status = AXObserverCreate(pid, { _, element, notification, refcon in
                    guard let refcon else { return }
                    let context = Unmanaged<Context>.fromOpaque(refcon).takeUnretainedValue()
                    var pid: pid_t = 0
                    AXUIElementGetPid(element, &pid)
                    context.handler(pid, notification as String)
                }, &observer)
                guard status == .success, let observer else { return }
                let application = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(application, 0.25)
                for event in Self.appEvents {
                    AXObserverAddNotification(observer, application, event as CFString, Unmanaged.passUnretained(self.context).toOpaque())
                }
                CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
                self.registrations[pid] = Registration(observer: observer, application: application, windows: [])
            }
            guard var registration = self.registrations[pid] else { return }
            for old in registration.windows where !windows.contains(where: { CFEqual($0, old) }) {
                for event in Self.windowEvents { AXObserverRemoveNotification(registration.observer, old, event as CFString) }
            }
            for window in windows where !registration.windows.contains(where: { CFEqual($0, window) }) {
                for event in Self.windowEvents {
                    AXObserverAddNotification(registration.observer, window, event as CFString, Unmanaged.passUnretained(self.context).toOpaque())
                }
            }
            registration.windows = windows
            self.registrations[pid] = registration
        }
    }
    public func observe(pid: pid_t, element: AXUIElement, notification: String) {
        enqueue { [weak self] in
            guard let self, let registration = self.registrations[pid] else { return }
            AXObserverAddNotification(registration.observer, element, notification as CFString, Unmanaged.passUnretained(self.context).toOpaque())
        }
    }
    public func remove(pid: pid_t) {
        enqueue { [weak self] in
            guard let registration = self?.registrations.removeValue(forKey: pid) else { return }
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(registration.observer), .defaultMode)
        }
    }
    public func stop() {
        lock.lock(); stopped = true; pending.removeAll()
        if let loop { CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(loop) }; CFRunLoopWakeUp(loop) }
        lock.unlock()
    }
}
