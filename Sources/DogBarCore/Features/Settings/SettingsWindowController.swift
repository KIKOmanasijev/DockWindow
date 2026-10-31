import AppKit
import SwiftUI

@MainActor final class SettingsVisibility: ObservableObject {
    @Published var isVisible = false
}

/// Owns the focusable settings window and preserves the application's visible Dock identity.
@MainActor public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let visibility = SettingsVisibility()
    private let settings: AppSettings

    public init(settings: AppSettings, permissions: PermissionsService, pinnedApps: PinnedAppsStore,
                onRestoreNativeDock: @escaping () -> Void, onShowPermissions: @escaping () -> Void) {
        self.settings = settings
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "DogBar Settings"
        window.titlebarAppearsTransparent = true
        window.identifier = NSUserInterfaceItemIdentifier("DogBar.Settings")
        window.minSize = NSSize(width: 820, height: 580)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DogBar.Settings")
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsRootView(settings: settings, permissions: permissions,
            visibility: visibility, pinnedApps: pinnedApps, onRestoreNativeDock: onRestoreNativeDock, onShowPermissions: onShowPermissions))
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    /// Brings Settings forward, including when DogBar is running as a menu bar app.
    public func show() {
        NSApp.setActivationPolicy(settings.showDogBarInDock ? .regular : .accessory)
        visibility.isVisible = true
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    public func windowDidMiniaturize(_ notification: Notification) { visibility.isVisible = false }
    public func windowDidDeminiaturize(_ notification: Notification) { visibility.isVisible = true }
    public func windowWillClose(_ notification: Notification) {
        visibility.isVisible = false
        SettingsShortcutRecording.activeRecorder?.finish()
        NSApp.setActivationPolicy(settings.showDogBarInDock ? .regular : .accessory)
    }
}

/// Accessory apps do not always participate in main-menu key-equivalent routing.
/// Keep standard window commands available while Settings is the key window.
@MainActor final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isKeyWindow, !SettingsShortcutRecording.isRecording,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": performClose(nil); return true
        case "q": NSApp.terminate(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
