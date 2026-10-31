import CoreGraphics
import Foundation

/// Moving the Dock to another display the way macOS does: hold the pointer against the Dock
/// edge of that display and keep pushing. Resting at the edge, or crossing into a neighbouring
/// display, never moves it. Coordinates are AppKit global points (y up).
public struct DockDisplayPush: Sendable {
    /// Push distance past the edge, in points. A deliberate nudge, not a brush past.
    public static let requiredDistance: CGFloat = 30
    /// A pause longer than this starts the push over.
    public static let maximumPause: TimeInterval = 0.35

    private var target: Int?
    private var pushed: CGFloat = 0
    private var lastPush: TimeInterval = 0

    public init() {}

    /// Feeds one pointer movement. `delta` is the event's raw motion: `dy` positive means down,
    /// as in `NSEvent.deltaY`. Returns the index of the display to move to once the push is done.
    public mutating func update(point: CGPoint, delta: CGVector, time: TimeInterval, screens: [CGRect],
                                current: Int?, position: DockPosition) -> Int? {
        guard let index = Self.outerEdgeScreen(point: point, screens: screens, position: position), index != current else {
            reset(); return nil
        }
        if target != index || time - lastPush > Self.maximumPause { target = index; pushed = 0 }
        let push = Self.pushDistance(delta, position: position)
        // Sliding along the edge neither counts nor cancels; only a pause or leaving the edge does.
        guard push > 0 else { return nil }
        pushed += push; lastPush = time
        guard pushed >= Self.requiredDistance else { return nil }
        reset()
        return index
    }

    public mutating func reset() { target = nil; pushed = 0; lastPush = 0 }

    /// The display whose Dock edge the pointer rests on, if that edge is a real outer edge.
    /// Where another display continues past it, the pointer simply crosses over instead.
    static func outerEdgeScreen(point: CGPoint, screens: [CGRect], position: DockPosition) -> Int? {
        for (index, frame) in screens.enumerated() {
            let beyond: CGPoint
            switch position {
            case .bottom:
                guard point.x >= frame.minX, point.x < frame.maxX, abs(point.y - frame.minY) <= 1.5 else { continue }
                beyond = CGPoint(x: point.x, y: frame.minY - 1)
            case .left:
                guard point.y >= frame.minY, point.y < frame.maxY, abs(point.x - frame.minX) <= 1.5 else { continue }
                beyond = CGPoint(x: frame.minX - 1, y: point.y)
            case .right:
                guard point.y >= frame.minY, point.y < frame.maxY, abs(point.x - (frame.maxX - 1)) <= 1.5 else { continue }
                beyond = CGPoint(x: frame.maxX + 0.5, y: point.y)
            }
            if !screens.contains(where: { $0.contains(beyond) }) { return index }
        }
        return nil
    }

    static func pushDistance(_ delta: CGVector, position: DockPosition) -> CGFloat {
        switch position {
        case .bottom: return delta.dy
        case .left: return -delta.dx
        case .right: return delta.dx
        }
    }
}
