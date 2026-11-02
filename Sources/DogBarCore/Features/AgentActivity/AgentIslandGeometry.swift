import AppKit

/// Where the island sits on one display, in screen coordinates (origin bottom-left).
/// On a display with a camera housing, the compact island is the housing plus a wing on each side,
/// so neither dog nor ring is ever drawn under the camera. Elsewhere it is a short pill under the
/// top edge, centered where the menu bar is usually empty.
public struct AgentIslandGeometry: Equatable, Sendable {
    public let screenFrame: CGRect
    /// Horizontal center of the housing (or the display).
    public let centerX: CGFloat
    public let hasNotch: Bool
    /// Width of the camera housing; zero without one.
    public let notchWidth: CGFloat
    /// Height of the compact island: the housing or menu bar height.
    public let barHeight: CGFloat
    public let collapsedSize: CGSize
    public let expandedWidth: CGFloat
    public let maximumExpandedHeight: CGFloat
    /// Transparent room around the shape for the shadow and spring overshoot. Never interactive.
    public static let margin: CGFloat = 28
    public static let wing: CGFloat = 46
    public static let preferredExpandedWidth: CGFloat = 420

    public init(screenFrame: CGRect, safeAreaTop: CGFloat, leftAuxiliary: CGRect?, rightAuxiliary: CGRect?, menuBarHeight: CGFloat) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = leftAuxiliary, let right = rightAuxiliary, right.minX > left.maxX {
            hasNotch = true
            notchWidth = right.minX - left.maxX
            centerX = (left.maxX + right.minX) / 2
            barHeight = safeAreaTop
            collapsedSize = CGSize(width: notchWidth + Self.wing * 2, height: safeAreaTop)
        } else {
            hasNotch = false
            notchWidth = 0
            centerX = screenFrame.midX
            barHeight = max(22, menuBarHeight)
            collapsedSize = CGSize(width: 176, height: barHeight)
        }
        let available = max(collapsedSize.width, screenFrame.width - 32)
        expandedWidth = min(available, max(Self.preferredExpandedWidth, collapsedSize.width + 40))
        maximumExpandedHeight = max(collapsedSize.height + 120, min(520, screenFrame.height * 0.66))
    }

    @MainActor public init(screen: NSScreen) {
        let thickness = NSStatusBar.system.thickness
        let menuBar = max(thickness, screen.frame.maxY - screen.visibleFrame.maxY)
        self.init(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                  leftAuxiliary: screen.auxiliaryTopLeftArea, rightAuxiliary: screen.auxiliaryTopRightArea,
                  menuBarHeight: menuBar)
    }

    /// Compact size for a number of visible dogs. On a notched display each extra dog widens
    /// both wings equally, so no dog is ever placed behind the camera housing.
    public func collapsedSize(dogs: Int) -> CGSize {
        guard hasNotch else { return collapsedSize }
        let extra = CGFloat(max(0, min(dogs, 3) - 1)) * Self.extraDogWidth
        return CGSize(width: collapsedSize.width + extra * 2, height: collapsedSize.height)
    }
    public static let extraDogWidth: CGFloat = 16

    /// The fixed panel: wide and tall enough for the largest expanded shape plus margins, top-attached.
    public var panelFrame: CGRect {
        let width = min(expandedWidth + Self.margin * 2, screenFrame.width)
        let height = maximumExpandedHeight + Self.margin
        let x = min(max(screenFrame.minX, centerX - width / 2), screenFrame.maxX - width)
        return CGRect(x: x.rounded(), y: screenFrame.maxY - height, width: width, height: height)
    }

    /// The visible shape for a given size, in screen coordinates. Top edge flush with the display.
    public func shapeFrame(size: CGSize) -> CGRect {
        CGRect(x: centerX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Horizontal offset of the island's center from the panel's center (non-zero only near display edges).
    public var contentOffsetX: CGFloat { centerX - panelFrame.midX }

    /// Which display hosts the island: the one with a camera housing, otherwise the menu bar display.
    @MainActor public static func preferredScreen(_ screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil } ?? screens.first
    }
}

/// Cmd+1…Cmd+9 and Escape while the pointer is over the open island. Pure, so the event tap stays trivial.
/// Only digit presses with exactly Command are taken; their key-ups are taken too. Escape is observed, never taken.
public struct AgentShortcutPolicy: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case select(slot: Int), collapse }
    public struct Decision: Equatable, Sendable {
        public var swallow = false
        public var action: Action?
    }
    /// ANSI virtual key codes for the 1…9 keys.
    static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    static let escape: UInt16 = 53
    private(set) var swallowedKeys: Set<UInt16> = []

    public init() {}

    public mutating func process(keyCode: UInt16, keyDown: Bool, command: Bool, otherModifiers: Bool, armed: Bool) -> Decision {
        if !keyDown { return Decision(swallow: swallowedKeys.remove(keyCode) != nil) }
        guard armed else { return Decision() }
        if keyCode == Self.escape, !command, !otherModifiers { return Decision(swallow: false, action: .collapse) }
        guard command, !otherModifiers, let slot = Self.digitKeys[keyCode] else { return Decision() }
        swallowedKeys.insert(keyCode)
        return Decision(swallow: true, action: .select(slot: slot))
    }
}
