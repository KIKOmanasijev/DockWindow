import AppKit
import SwiftUI

/// Owns the focusable settings window without changing the app's long-term activation policy.
@MainActor public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var previousPolicy: NSApplication.ActivationPolicy?

    public init(settings: AppSettings, permissions: PermissionsService, pinnedApps: PinnedAppsStore,
                onRestoreNativeDock: @escaping () -> Void, onShowPermissions: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "DockWindow Settings"
        window.identifier = NSUserInterfaceItemIdentifier("DockWindow.Settings")
        window.minSize = NSSize(width: 720, height: 520)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DockWindow.Settings")
        window.contentView = NSHostingView(rootView: SettingsRootView(settings: settings, permissions: permissions,
            pinnedApps: pinnedApps, onRestoreNativeDock: onRestoreNativeDock, onShowPermissions: onShowPermissions))
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    /// Brings Settings forward, including when DockWindow is running as a menu bar app.
    public func show() {
        if previousPolicy == nil { previousPolicy = NSApp.activationPolicy() }
        NSApp.setActivationPolicy(.accessory)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    public func windowWillClose(_ notification: Notification) {
        if let previousPolicy { NSApp.setActivationPolicy(previousPolicy) }
        previousPolicy = nil
    }
}
