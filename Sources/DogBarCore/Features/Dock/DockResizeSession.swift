import Foundation

/// Follows screen-space movement, independent of the panel relayout beneath the pointer.
struct DockResizeSession {
    let initialSize: CGFloat
    let origin: CGPoint
    let position: DockPosition
    private(set) var currentSize: CGFloat
    private var previousCoordinate: CGFloat

    init(size: CGFloat, origin: CGPoint, position: DockPosition) {
        initialSize = Self.clamp(size)
        currentSize = initialSize
        self.origin = origin
        self.position = position
        previousCoordinate = Self.coordinate(origin, position: position)
    }

    mutating func size(at point: CGPoint) -> CGFloat {
        let coordinate = Self.coordinate(point, position: position)
        guard coordinate.isFinite else { return currentSize }
        let delta = coordinate - previousCoordinate
        guard delta.isFinite else { return currentSize }
        previousCoordinate = coordinate
        // Consume every movement, including movement past a limit. Reversing from
        // either limit therefore responds immediately instead of unwinding overshoot.
        currentSize = Self.clamp(currentSize + delta)
        return currentSize
    }

    mutating func end(at point: CGPoint, cancelled: Bool) -> CGFloat {
        if cancelled { currentSize = initialSize; return initialSize }
        return size(at: point)
    }

    private static func coordinate(_ point: CGPoint, position: DockPosition) -> CGFloat {
        switch position {
        case .bottom: return point.y
        case .left: return point.x
        case .right: return -point.x
        }
    }
    private static func clamp(_ size: CGFloat) -> CGFloat {
        min(128, max(16, size.isFinite ? size : 48))
    }
}
