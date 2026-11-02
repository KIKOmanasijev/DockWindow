import CoreGraphics
import Foundation

/// What the Settings recorder learns from one captured key event.
internal enum ShortcutCaptureEvent: Equatable { case captured(KeyboardShortcut), cancelled }
/// Captured event plus whether the original event must be swallowed.
internal struct ShortcutCaptureDecision: Equatable {
    var event: ShortcutCaptureEvent?
    var swallow = false
}

/// Pure capture state for one recording. It claims exactly one modifier shortcut or Escape,
/// then passes every new key through, so a delayed stop cannot keep eating input.
/// Modifier-free keys pass through so the recorder's local monitor can reject them.
internal struct ShortcutCaptureState {
    internal private(set) var isComplete = false
    internal private(set) var suppressedKeys: Set<UInt16> = []

    internal mutating func process(kind: HotkeyEventKind, keyCode: UInt16 = 0,
                                   flags: HotkeyModifiers = [], isRepeat: Bool = false) -> ShortcutCaptureDecision {
        switch kind {
        case .tapDisabled, .flagsChanged: return .init()
        case .keyUp: return .init(swallow: suppressedKeys.remove(keyCode) != nil)
        case .keyDown:
            // A repeat of the claimed key must not leak to the frontmost app.
            if suppressedKeys.contains(keyCode) { return .init(swallow: true) }
            let modifiers = flags.intersection(.relevant)
            let isEscape = keyCode == 53
            guard !isComplete, !isRepeat, isEscape || !modifiers.isEmpty else { return .init() }
            isComplete = true
            suppressedKeys.insert(keyCode)
            return .init(event: isEscape ? .cancelled : .captured(KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)),
                         swallow: true)
        }
    }
}

/// A session event tap that exists only while a Settings recorder is focused, so reserved
/// shortcuts such as Command+Tab reach DogBar instead of the system app switcher.
/// It never synthesizes input. Creation needs Accessibility; start returns false without it.
@MainActor
internal final class ShortcutCaptureEventTap {
    private var worker: ShortcutCaptureWorker?

    /// Starts capturing. Events arrive on the main thread until stop.
    internal func start(onEvent: @escaping @MainActor (ShortcutCaptureEvent) -> Void) -> Bool {
        stop()
        let worker = ShortcutCaptureWorker(onEvent: onEvent)
        guard worker.start() else { return false }
        self.worker = worker
        return true
    }

    /// Removes the tap, waits for its thread to exit and drops queued events.
    internal func stop() {
        worker?.stop()
        worker = nil
    }

    deinit { worker?.stop() }
}

/// The lock protects capture state and lifecycle. The tap lives only on its own thread.
private final class ShortcutCaptureWorker {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let onEvent: @MainActor (ShortcutCaptureEvent) -> Void
    private var state = ShortcutCaptureState()
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var running = false

    fileprivate init(onEvent: @escaping @MainActor (ShortcutCaptureEvent) -> Void) { self.onEvent = onEvent }

    fileprivate func start() -> Bool {
        let thread = Thread { self.run() }
        thread.name = "DogBar shortcut recorder tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        lock.lock()
        let result = running
        lock.unlock()
        if !result { finished.wait() }
        return result
    }

    fileprivate func stop() {
        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(runLoop) }
            CFRunLoopWakeUp(runLoop)
        }
        lock.unlock()
        finished.wait()
    }

    private func run() {
        defer { finished.signal() }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ShortcutCaptureWorker>.fromOpaque(context).takeUnretainedValue()
                    .receive(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            ready.signal()
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(nil, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            ready.signal()
            return
        }
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .defaultMode)
        lock.lock()
        tap = eventTap
        runLoop = loop
        running = true
        lock.unlock()
        CGEvent.tapEnable(tap: eventTap, enable: true)
        ready.signal()
        CFRunLoopRun()
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFRunLoopRemoveSource(loop, source, .defaultMode)
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(eventTap)
        lock.lock()
        running = false
        tap = nil
        runLoop = nil
        lock.unlock()
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let kind: HotkeyEventKind
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput: kind = .tapDisabled
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: return Unmanaged.passUnretained(event)
        }
        lock.lock()
        defer { lock.unlock() }
        if kind == .tapDisabled {
            if running, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // A stopping tap passes everything through.
        guard running else { return Unmanaged.passUnretained(event) }
        let decision = state.process(kind: kind,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: HotkeyModifiers(rawValue: event.flags.rawValue),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        if let captured = decision.event {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let deliver = self.running
                self.lock.unlock()
                if deliver { self.onEvent(captured) }
            }
        }
        return decision.swallow ? nil : Unmanaged.passUnretained(event)
    }
}
