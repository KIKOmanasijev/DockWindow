import Foundation

/// Pure Dock geometry in AppKit coordinates. The inward axis points away from the screen edge.
public struct DockLayout {
    public var iconFrames: [CGRect]
    public var background: CGRect
    public var position: DockPosition
    private var cornerRadius: CGFloat = 0
    public init(kinds: [DockItem.Kind], bounds: CGRect, position: DockPosition, baseSize: CGFloat,
                maximumSize: CGFloat, pointer: CGPoint? = nil) {
        self.position = position
        guard !kinds.isEmpty else { iconFrames = []; background = .zero; return }
        cornerRadius = min(30, baseSize * 0.3)
        let horizontal = position == .bottom
        let length = horizontal ? bounds.width : bounds.height
        let base = min(128, max(16, baseSize.isFinite ? baseSize : 48))
        // Fit crowded Docks without putting inaccessible icons offscreen.
        let units = kinds.reduce(CGFloat(0)) { $0 + ($1 == .separator ? 0.25 : 1) }
        let size = min(base, max(4, (length - 16 - CGFloat(max(0, kinds.count - 1)) * 4) / max(1, units)))
        let widths = kinds.map { $0 == .separator ? size * 0.25 : size }
        let restLength = widths.reduce(0, +) + CGFloat(max(0, kinds.count - 1)) * 4
        var cursor = (length - restLength) / 2
        let coordinate = pointer.map { horizontal ? $0.x - bounds.minX : bounds.maxY - $0.y }
        let sizes = widths.enumerated().map { index, width -> CGFloat in
            defer { cursor += width + 4 }
            guard kinds[index] != .separator, let coordinate else { return width }
            let scale = MagnificationPolicy.scale(distance: Double((coordinate - cursor - width / 2) / size), baseSize: Double(base), maximumSize: Double(maximumSize))
            return width * CGFloat(scale)
        }
        let requested = sizes.reduce(0, +) + CGFloat(max(0, kinds.count - 1)) * 4
        let spacing = CGFloat(max(0, kinds.count - 1)) * 4
        let fit = min(1, max(1, length - 16 - spacing) / max(1, requested - spacing))
        let total = sizes.reduce(0, +) * fit + CGFloat(max(0, kinds.count - 1)) * 4
        cursor = (length - total) / 2
        let start = cursor
        iconFrames = sizes.enumerated().map { index, width in
            let side = width * fit
            defer { cursor += side + 4 }
            let depth = kinds[index] == .separator ? size * 0.7 : side
            switch position {
            case .bottom: return CGRect(x: bounds.minX + cursor, y: bounds.minY + 14, width: side, height: depth)
            case .left: return CGRect(x: bounds.minX + 14, y: bounds.maxY - cursor - side, width: depth, height: side)
            case .right: return CGRect(x: bounds.maxX - 14 - depth, y: bounds.maxY - cursor - side, width: depth, height: side)
            }
        }
        let thickness = size + 24
        switch position {
        case .bottom: background = CGRect(x: bounds.minX + start - 8, y: bounds.minY + 4, width: total + 16, height: thickness)
        case .left: background = CGRect(x: bounds.minX + 4, y: bounds.maxY - start - total - 8, width: thickness, height: total + 16)
        case .right: background = CGRect(x: bounds.maxX - 4 - thickness, y: bounds.maxY - start - total - 8, width: thickness, height: total + 16)
        }
    }
    /// Separator gaps are reserved for resizing. Without one, use the inward material edge.
    public func resizeHandle(kinds: [DockItem.Kind]) -> CGRect {
        guard !background.isEmpty else { return .zero }
        if let index = kinds.firstIndex(of: .separator), iconFrames.indices.contains(index) {
            let frame = iconFrames[index]
            return position == .bottom ? frame.insetBy(dx: -3, dy: 0) : frame.insetBy(dx: 0, dy: -3)
        }
        switch position {
        case .bottom: return CGRect(x: background.midX - 12, y: background.maxY - 8, width: 24, height: 6)
        case .left: return CGRect(x: background.maxX - 8, y: background.midY - 12, width: 6, height: 24)
        case .right: return CGRect(x: background.minX + 2, y: background.midY - 12, width: 6, height: 24)
        }
    }
    /// Only the visible material and icons intercept input, never their transparent bounding hull.
    public func containsInteractivePoint(_ point: CGPoint) -> Bool {
        Self.roundedContains(point, rect: background, radius: cornerRadius) || iconFrames.contains { $0.contains(point) }
    }
    /// Matches the material's rounded corners so transparent corners pass through.
    static func roundedContains(_ point: CGPoint, rect: CGRect, radius: CGFloat) -> Bool {
        guard !rect.isEmpty, rect.contains(point) else { return false }
        let r = min(max(0, radius), min(rect.width, rect.height) / 2)
        let center = CGPoint(x: min(max(point.x, rect.minX + r), rect.maxX - r),
                             y: min(max(point.y, rect.minY + r), rect.maxY - r))
        return hypot(point.x - center.x, point.y - center.y) <= r
    }
    public func hitTest(_ point: CGPoint, kinds: [DockItem.Kind]) -> Int? {
        iconFrames.indices.first { kinds.indices.contains($0) && kinds[$0] != .separator && iconFrames[$0].contains(point) }
    }
    public func insertionIndex(at point: CGPoint) -> Int {
        return iconFrames.firstIndex { position == .bottom ? point.x < $0.midX : point.y > $0.midY } ?? iconFrames.count
    }
    public func isDragRemoval(at point: CGPoint, distance: CGFloat = 60) -> Bool {
        let dx = max(background.minX - point.x, 0, point.x - background.maxX)
        let dy = max(background.minY - point.y, 0, point.y - background.maxY)
        return hypot(dx, dy) > distance
    }
    public static func panelFrame(screen: CGRect, position: DockPosition, depth: CGFloat = 210) -> CGRect {
        switch position {
        case .bottom: return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: depth)
        case .left: return CGRect(x: screen.minX, y: screen.minY, width: depth, height: screen.height)
        case .right: return CGRect(x: screen.maxX - depth, y: screen.minY, width: depth, height: screen.height)
        }
    }
    public static func hiddenFrame(_ frame: CGRect, position: DockPosition) -> CGRect {
        switch position {
        case .bottom: return frame.offsetBy(dx: 0, dy: -frame.height)
        case .left: return frame.offsetBy(dx: -frame.width, dy: 0)
        case .right: return frame.offsetBy(dx: frame.width, dy: 0)
        }
    }
    public static func touchesEdge(_ point: CGPoint, screen: CGRect, position: DockPosition) -> Bool {
        guard screen.insetBy(dx: -1, dy: -1).contains(point) else { return false }
        switch position {
        case .bottom: return point.y <= screen.minY + 2
        case .left: return point.x <= screen.minX + 2
        case .right: return point.x >= screen.maxX - 2
        }
    }
}
