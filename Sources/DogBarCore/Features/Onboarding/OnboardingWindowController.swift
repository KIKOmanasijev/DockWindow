import AppKit
import SwiftUI

/// Owns the one onboarding window for the app's lifetime.
///
/// Focus: DogBar is usually an accessory app, and an accessory app's window can open behind the
/// app the user launched it from. While the wizard is visible the app runs as a regular app
/// (so it is in Cmd+Tab when the user returns from System Settings). Presenting activates once and
/// retries briefly, because activation-policy changes and activation complete asynchronously. The
/// retry stops as soon as the user has moved to another app. Permission changes never move focus.
@MainActor public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    public let model: OnboardingModel
    private let store: OnboardingStore
    private let permissions: PermissionsService
    private let settings: AppSettings
    private var finished = false
    private var focusTask: Task<Void, Never>?
    /// Called when the window shows or hides, to update activation policy and feature state.
    public var onVisibilityChanged: (() -> Void)?
    public private(set) var isShowing = false

    public init(store: OnboardingStore, permissions: PermissionsService, settings: AppSettings) {
        self.store = store; self.permissions = permissions; self.settings = settings
        model = OnboardingModel(store: store)
        let window = OnboardingWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                                      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
        window.title = "Welcome to DogBar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("DogBar.Onboarding")
        window.collectionBehavior.insert(.moveToActiveSpace)
        super.init(window: window)
        let host = NSHostingController(rootView: OnboardingView(model: model, permissions: permissions, settings: settings))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(OnboardingView.size)
        window.delegate = self
        model.onFinish = { [weak self] in self?.complete() }
    }
    required init?(coder: NSCoder) { nil }

    /// Dock replacement and the switcher wait until the first tour or a recovery flow is finished
    /// or closed, so nothing changes under the reader. A replayed tour leaves running features alone.
    public var holdsFeatures: Bool { isShowing && (model.mode == .firstRun || model.mode == .recovery) }

    /// Shows the wizard in `mode`. A first-run tour already on screen is never replaced by a shorter flow.
    public func present(_ mode: OnboardingMode) {
        if isShowing, model.mode == .firstRun, mode != .tour { bringForward(); return }
        if !(isShowing && model.mode == mode) {
            let inputs = OnboardingPlan.Inputs(installed: permissions.installLocation.isInstalled, accessibility: permissions.accessibility,
                                               screenRecording: permissions.screenRecording, privacyAsked: settings.telemetryAsked)
            let steps = OnboardingPlan.steps(for: mode, inputs)
            let start = mode == .firstRun ? OnboardingPlan.resumeIndex(for: store.resumeStep, in: steps) : 0
            model.configure(mode: mode, steps: steps, start: start)
        }
        finished = false
        let wasShowing = isShowing
        isShowing = true
        if !wasShowing { window?.center(); onVisibilityChanged?() }
        bringForward()
    }

    private func bringForward() {
        guard let window else { return }
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        // Visible above the launching app even before activation is granted.
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        let launcher = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        focusTask?.cancel()
        focusTask = Task { @MainActor [weak self, weak window] in
            for delay in [120, 350] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self, let window, self.isShowing, window.isVisible else { return }
                if NSApp.isActive && window.isKeyWindow { return }
                // The user went somewhere else (for example System Settings): leave them there.
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                guard front == nil || front == own || front == launcher else { return }
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func complete() {
        finished = true
        if model.mode != .privacyOnly { store.markCompleted() }
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        focusTask?.cancel()
        // Closing the first tour early: once DogBar can run, don't bring the tour back. Without
        // permissions, keep the saved step so the next launch resumes there.
        if !finished, model.mode == .firstRun, permissions.isGranted { store.markCompleted() }
        isShowing = false
        DispatchQueue.main.async { [weak self] in self?.onVisibilityChanged?() }
    }
}

/// Keeps Cmd+W and Cmd+Q working while DogBar runs without its own menu bar focus.
@MainActor final class OnboardingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isKeyWindow, event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": performClose(nil); return true
        case "q": NSApp.terminate(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
