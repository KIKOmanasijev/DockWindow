import Foundation

/// Uses screen coordinates so panel relayout cannot change the drag's reference point.
struct DockResizeSession {
    let initialSize: CGFloat
    let origin: CGPoint
    let position: DockPosition

    init(size: CGFloat, origin: CGPoint, position: DockPosition) {
        initialSize = Self.clamp(size)
        self.origin = origin
        self.position = position
    }

    func size(at point: CGPoint) -> CGFloat {
        let delta: CGFloat
        switch position {
        case .bottom: delta = point.y - origin.y
        case .left: delta = point.x - origin.x
        case .right: delta = origin.x - point.x
        }
        guard delta.isFinite else { return initialSize }
        return Self.clamp(initialSize + delta)
    }

    func end(at point: CGPoint, cancelled: Bool) -> CGFloat {
        cancelled ? initialSize : size(at: point)
    }

    private static func clamp(_ size: CGFloat) -> CGFloat {
        min(128, max(16, size.isFinite ? size : 48))
    }
}
