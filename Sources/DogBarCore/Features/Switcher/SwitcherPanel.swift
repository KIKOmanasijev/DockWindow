import AppKit

/// Reused nonactivating surface that never steals the application's key window.
@MainActor public final class SwitcherPanel: NSPanel {
    public init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        animationBehavior = .none
    }
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
