import Foundation

/// AppKit invokes menu targets before popUpContextMenu finishes tracking.
/// Keep window actions out of that tracking session, including submenu actions.
@MainActor final class DockMenuSession {
    private var action: (() -> Void)?
    func select(_ action: @escaping () -> Void) { self.action = action }
    func finish() {
        let selected = action
        action = nil
        selected?()
    }
}
