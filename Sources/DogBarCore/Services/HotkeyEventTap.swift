import CoreGraphics
import Foundation

/// Pure ownership state for a single modifier-held switcher session.
/// Key-up ownership survives commit/cancel, but disabling delivery clears all ownership.
internal struct HotkeySessionState {
    internal private(set) var isActive = false
    internal private(set) var heldShortcut: KeyboardShortcut?
    internal private(set) var suppressedKeys: Set<UInt16> = []

    internal mutating func endSession() {
        isActive = false
        heldShortcut = nil
    }

    internal mutating func reset() {
        isActive = false
        heldShortcut = nil
        suppressedKeys.removeAll()
    }

    internal mutating func process(kind: HotkeyEventKind, keyCode: UInt16 = 0,
                                   flags: HotkeyModifiers = [], isRepeat: Bool = false,
                                   configuration: HotkeyConfiguration,
                                   canDeliver: Bool) -> HotkeyDecision {
        if kind == .tapDisabled { return .init(command: .reenableTap) }
        guard canDeliver && configuration.enabled else { reset(); return .init() }
        if kind == .keyUp {
            return .init(swallow: suppressedKeys.remove(keyCode) != nil)
        }
        // A repeat belonging to an already ended session must not reopen the UI.
        if kind == .keyDown && isRepeat && !isActive && suppressedKeys.contains(keyCode) {
            return .init(swallow: true)
        }
        var decodingConfiguration = configuration
        if let heldShortcut {
            decodingConfiguration.shortcut = heldShortcut
            decodingConfiguration.sameAppEnabled = false
        }
        let decision = HotkeyPolicy.decode(kind: kind, keyCode: keyCode, flags: flags,
            isSessionActive: isActive, heldModifiers: heldShortcut?.modifiers,
            configuration: decodingConfiguration)
        if case let .begin(_, sameAppOnly)? = decision.command {
            let shortcut = sameAppOnly ? configuration.sameAppShortcut : configuration.shortcut
            // A modifier-free shortcut has no release transition to commit the session.
            guard !shortcut.modifiers.intersection(.relevant).isEmpty else { return .init() }
            heldShortcut = shortcut
            isActive = true
        }
        if decision.command == .commit || decision.command == .cancel {
            isActive = false
            heldShortcut = nil
        }
        if kind == .keyDown && decision.swallow { suppressedKeys.insert(keyCode) }
        return decision
    }
}

/// Owns a session event tap on a dedicated thread. It never performs UI or AX work there.
/// Call update with enabled=true only while the command receiver can present the switcher.
/// The initial configuration is disabled. Stop and disabling cancel any delivered session.
@MainActor
public final class HotkeyEventTap {
    private let onCommand: (SwitcherCommand) -> Void
    private var worker: HotkeyTapWorker?
    private var configuration: HotkeyConfiguration
    private var hasDeliveredSession = false

    public init(onCommand: @escaping (SwitcherCommand) -> Void) {
        self.onCommand = onCommand
        var configuration = HotkeyConfiguration()
        configuration.enabled = false
        self.configuration = configuration
    }

    /// Returns false if macOS cannot create the tap. Does not request permissions.
    @discardableResult
    public func start() -> Bool {
        if let worker, worker.isRunning { return true }
        self.worker = nil
        cancelDeliveredSession()
        let worker = HotkeyTapWorker(configuration: configuration) { [weak self] command in
            guard let self else { return }
            if case .begin = command { self.hasDeliveredSession = true }
            if command == .commit || command == .cancel { self.hasDeliveredSession = false }
            self.onCommand(command)
        }
        guard worker.start() else { return false }
        self.worker = worker
        return true
    }

    /// Invalidates queued callbacks, removes the tap and waits for its thread to exit.
    public func stop() {
        worker?.stop()
        worker = nil
        cancelDeliveredSession()
    }

    /// Publishes a complete value atomically with respect to event decoding.
    /// Shortcut edits retain the trigger that began an existing session.
    public func update(configuration: HotkeyConfiguration) {
        self.configuration = configuration
        worker?.update(configuration: configuration)
        if !configuration.enabled { cancelDeliveredSession() }
    }

    /// End UI ownership while retaining key-up suppression for keys already consumed.
    public func endSession() {
        hasDeliveredSession = false
        worker?.endSession()
    }

    private func cancelDeliveredSession() {
        guard hasDeliveredSession else { return }
        hasDeliveredSession = false
        onCommand(.cancel)
    }

    deinit { worker?.stop() }
}

/// The lock protects configuration, session state, lifecycle and delivery generation.
/// Tap/source creation and destruction happen exclusively on the owning thread.
private final class HotkeyTapWorker {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let onCommand: @MainActor (SwitcherCommand) -> Void
    private var configuration: HotkeyConfiguration
    private var session = HotkeySessionState()
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var running = false
    private var generation: UInt64 = 0

    fileprivate init(configuration: HotkeyConfiguration,
                     onCommand: @escaping @MainActor (SwitcherCommand) -> Void) {
        self.configuration = configuration
        self.onCommand = onCommand
    }

    fileprivate var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    fileprivate func start() -> Bool {
        let thread = Thread { self.run() }
        thread.name = "DogBar hotkey event tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        lock.lock()
        let result = running
        lock.unlock()
        if !result { finished.wait() }
        return result
    }

    fileprivate func update(configuration: HotkeyConfiguration) {
        lock.lock()
        self.configuration = configuration
        if !configuration.enabled {
            generation &+= 1
            session.reset()
        }
        lock.unlock()
    }

    fileprivate func endSession() {
        lock.lock()
        generation &+= 1
        session.endSession()
        lock.unlock()
    }

    fileprivate func stop() {
        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        generation &+= 1
        session.reset()
        if let runLoop {
            // A queued stop also covers the interval before CFRunLoopRun enters.
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
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<HotkeyTapWorker>.fromOpaque(context).takeUnretainedValue()
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
        generation &+= 1
        session.reset()
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
        case .flagsChanged: kind = .flagsChanged
        default: return Unmanaged.passUnretained(event)
        }
        lock.lock()
        defer { lock.unlock() }
        if kind == .tapDisabled {
            if running, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let decision = session.process(kind: kind,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: HotkeyModifiers(rawValue: event.flags.rawValue),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            configuration: configuration, canDeliver: running)
        if let command = decision.command {
            let expectedGeneration = generation
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let deliver = self.running && self.configuration.enabled && self.generation == expectedGeneration
                self.lock.unlock()
                if deliver { self.onCommand(command) }
            }
        }
        return decision.swallow ? nil : Unmanaged.passUnretained(event)
    }
}
