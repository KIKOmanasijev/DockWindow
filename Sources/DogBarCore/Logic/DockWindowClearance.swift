import Foundation

/// AX coordinates: origin at the primary display's top-left, y increases downwards.
public enum DockWindowClearance {
    public static func adjustedFrame(_ frame: CGRect, visible: CGRect, screen: CGRect,
                                     edge: DockPosition, depth: CGFloat) -> CGRect? {
        guard !frame.isEmpty, depth.isFinite, depth > 0, visible.intersects(frame) else { return nil }
        let tolerance: CGFloat = 12
        var target = frame
        switch edge {
        case .bottom:
            let bottom = min(visible.maxY, screen.maxY - depth)
            // Only full-height/maximized windows, not ordinary windows near the Dock.
            guard abs(frame.minY - visible.minY) <= tolerance,
                  frame.maxY >= visible.maxY - tolerance, frame.maxY > bottom + 1 else { return nil }
            target.size.height = bottom - frame.minY
        case .left:
            let left = max(visible.minX, screen.minX + depth)
            guard abs(frame.minX - visible.minX) <= tolerance,
                  abs(frame.maxX - visible.maxX) <= tolerance, frame.minX < left - 1 else { return nil }
            target.origin.x = left; target.size.width = frame.maxX - left
        case .right:
            let right = min(visible.maxX, screen.maxX - depth)
            guard abs(frame.minX - visible.minX) <= tolerance,
                  abs(frame.maxX - visible.maxX) <= tolerance, frame.maxX > right + 1 else { return nil }
            target.size.width = right - frame.minX
        }
        guard target.width >= 200, target.height >= 100 else { return nil }
        return target
    }
}
