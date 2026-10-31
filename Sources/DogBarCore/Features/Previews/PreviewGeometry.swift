import Foundation

/// AppKit global point geometry. Never multiply origins by a display's backing scale.
public enum PreviewGeometry {
    public static func edge(anchor: CGRect, screen: CGRect) -> DockPosition {
        let distances: [(DockPosition, CGFloat)] = [(.bottom, abs(anchor.midY - screen.minY)), (.left, abs(anchor.midX - screen.minX)), (.right, abs(screen.maxX - anchor.midX))]
        return distances.min { $0.1 < $1.1 }?.0 ?? .bottom
    }
    public static func frame(size: CGSize, anchor: CGRect, bounds: CGRect, edge: DockPosition, gap: CGFloat = 10) -> CGRect {
        let width = min(max(0, size.width), bounds.width)
        let height = min(max(0, size.height), bounds.height)
        var origin: CGPoint
        switch edge {
        case .bottom: origin = CGPoint(x: anchor.midX - width / 2, y: anchor.maxY + gap)
        case .left: origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - height / 2)
        case .right: origin = CGPoint(x: anchor.minX - gap - width, y: anchor.midY - height / 2)
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - height)
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
    /// A tapered corridor between the facing edges, including a small pointer tolerance.
    public static func bridgeContains(_ point: CGPoint, anchor: CGRect, panel: CGRect, edge: DockPosition, tolerance: CGFloat = 6) -> Bool {
        let a = anchor.insetBy(dx: -tolerance, dy: -tolerance)
        let p = panel.insetBy(dx: -tolerance, dy: -tolerance)
        if a.contains(point) || p.contains(point) { return true }
        let vertices: [CGPoint]
        switch edge {
        case .bottom: vertices = [CGPoint(x: a.minX, y: a.maxY), CGPoint(x: a.maxX, y: a.maxY), CGPoint(x: p.maxX, y: p.minY), CGPoint(x: p.minX, y: p.minY)]
        case .left: vertices = [CGPoint(x: a.maxX, y: a.minY), CGPoint(x: p.minX, y: p.minY), CGPoint(x: p.minX, y: p.maxY), CGPoint(x: a.maxX, y: a.maxY)]
        case .right: vertices = [CGPoint(x: p.maxX, y: p.minY), CGPoint(x: a.minX, y: a.minY), CGPoint(x: a.minX, y: a.maxY), CGPoint(x: p.maxX, y: p.maxY)]
        }
        var inside = false
        var j = vertices.count - 1
        for i in vertices.indices {
            let v = vertices[i], w = vertices[j]
            if (v.y > point.y) != (w.y > point.y), point.x < (w.x - v.x) * (point.y - v.y) / (w.y - v.y) + v.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
