import CoreGraphics
import Foundation

/// A keyboard tap that exists only while the island is open. It takes Cmd+1…Cmd+9 only while
/// `armed` (the pointer is over the island), and passes everything else through untouched,
/// so other apps keep their Command-number shortcuts. Needs Accessibility; without it the dots still work.
@MainActor final class AgentShortcutTap {
    private let worker: Worker
    init(onAction: @escaping @MainActor (AgentShortcutPolicy.Action) -> Void) {
        worker = Worker(onAction: onAction)
    }
    var armed: Bool {
        get { worker.armed }
        set { worker.armed = newValue }
    }
    @discardableResult func start() -> Bool { worker.start() }
    func stop() { worker.stop() }
    deinit { worker.stop() }

    private final class Worker: @unchecked Sendable {
        private let lock = NSLock()
        private let onAction: @MainActor (AgentShortcutPolicy.Action) -> Void
        private var policy = AgentShortcutPolicy()
        private var armedValue = false
        private var running = false
        private var runLoop: CFRunLoop?
        private var tap: CFMachPort?
        private let ready = DispatchSemaphore(value: 0)
        private let finished = DispatchSemaphore(value: 0)

        init(onAction: @escaping @MainActor (AgentShortcutPolicy.Action) -> Void) { self.onAction = onAction }

        var armed: Bool {
            get { lock.lock(); defer { lock.unlock() }; return armedValue }
            set { lock.lock(); armedValue = newValue; lock.unlock() }
        }

        func start() -> Bool {
            lock.lock()
            if running { lock.unlock(); return true }
            lock.unlock()
            let thread = Thread { [self] in run() }
            thread.name = "DogBar agent island keys"
            thread.qualityOfService = .userInteractive
            thread.start()
            ready.wait()
            lock.lock(); let ok = running; lock.unlock()
            if !ok { finished.wait() }
            return ok
        }

        func stop() {
            lock.lock()
            guard running, let runLoop else { lock.unlock(); return }
            running = false
            armedValue = false
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(runLoop) }
            CFRunLoopWakeUp(runLoop)
            lock.unlock()
            finished.wait()
        }

        private func run() {
            defer { finished.signal() }
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let worker = Unmanaged<Worker>.fromOpaque(context).takeUnretainedValue()
                return worker.handle(type: type, event: event)
            }, userInfo: context) else { ready.signal(); return }
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            lock.lock(); self.tap = tap; runLoop = loop; running = true; lock.unlock()
            ready.signal()
            CFRunLoopRun()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(tap)
            lock.lock(); self.tap = nil; runLoop = nil; lock.unlock()
        }

        private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                lock.lock(); let tap = self.tap; lock.unlock()
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
            let flags = event.flags
            let other: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            lock.lock()
            let decision = policy.process(keyCode: keyCode, keyDown: type == .keyDown, command: flags.contains(.maskCommand),
                                          otherModifiers: !flags.intersection(other).isEmpty, armed: armedValue && running)
            lock.unlock()
            if let action = decision.action {
                let onAction = self.onAction
                DispatchQueue.main.async { MainActor.assumeIsolated { onAction(action) } }
            }
            return decision.swallow ? nil : Unmanaged.passUnretained(event)
        }
    }
}
