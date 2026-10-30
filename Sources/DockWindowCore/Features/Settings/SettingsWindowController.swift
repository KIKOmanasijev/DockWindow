import AppKit
import SwiftUI

@MainActor final class SettingsVisibility: ObservableObject {
    @Published var isVisible = false
}

/// Owns the focusable settings window and preserves the application's visible Dock identity.
@MainActor public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let visibility = SettingsVisibility()

    public init(settings: AppSettings, permissions: PermissionsService, pinnedApps: PinnedAppsStore,
                onRestoreNativeDock: @escaping () -> Void, onShowPermissions: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "DogBar Settings"
        window.identifier = NSUserInterfaceItemIdentifier("DockWindow.Settings")
        window.minSize = NSSize(width: 720, height: 520)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DockWindow.Settings")
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsRootView(settings: settings, permissions: permissions,
            visibility: visibility, pinnedApps: pinnedApps, onRestoreNativeDock: onRestoreNativeDock, onShowPermissions: onShowPermissions))
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    /// Brings Settings forward, including when DockWindow is running as a menu bar app.
    public func show() {
        NSApp.setActivationPolicy(.regular)
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
        NSApp.setActivationPolicy(.regular)
    }
}
