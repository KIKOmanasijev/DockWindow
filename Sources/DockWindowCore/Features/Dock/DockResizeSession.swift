import Foundation

/// Uses screen coordinates so panel relayout cannot change the drag's reference point.
struct DockResizeSession {
    let initialSize: CGFloat
    let origin: CGPoint
    let position: DockPosition
    private(set) var currentSize: CGFloat
    private static let step: CGFloat = 4
    private static let releaseDistance: CGFloat = 3.5

    init(size: CGFloat, origin: CGPoint, position: DockPosition) {
        initialSize = Self.clamp(size)
        currentSize = Self.clamp(size)
        self.origin = origin
        self.position = position
    }

    mutating func size(at point: CGPoint) -> CGFloat {
        let delta: CGFloat
        switch position {
        case .bottom: delta = point.y - origin.y
        case .left: delta = point.x - origin.x
        case .right: delta = origin.x - point.x
        }
        guard delta.isFinite else { return currentSize }
        let raw = Self.clamp(initialSize + delta)
        // Hold each size until the pointer pulls past its detent. Separate
        // release thresholds keep tiny reversals from flickering between sizes.
        if raw == 16 || raw == 128 {
            currentSize = raw
        } else if abs(raw - currentSize) >= Self.releaseDistance {
            currentSize = Self.clamp(initialSize + (delta / Self.step).rounded() * Self.step)
        }
        return currentSize
    }

    mutating func end(at point: CGPoint, cancelled: Bool) -> CGFloat {
        if cancelled { currentSize = initialSize; return initialSize }
        return size(at: point)
    }

    private static func clamp(_ size: CGFloat) -> CGFloat {
        min(128, max(16, size.isFinite ? size : 48))
    }
}
