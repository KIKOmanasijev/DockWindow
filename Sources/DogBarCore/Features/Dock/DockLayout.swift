import Foundation

/// Pure Dock geometry in AppKit coordinates. The inward axis points away from the screen edge.
public struct DockLayout {
    public var iconFrames: [CGRect]
    public var background: CGRect
    public var position: DockPosition
    /// Corner radius of the material, from the same measured proportions as its thickness.
    public private(set) var cornerRadius: CGFloat = 0
    /// Resting tile size after fitting a crowded Dock; magnification never changes it.
    public private(set) var iconSize: CGFloat = 0
    /// Material padding around each icon at this layout's (crowd-fitted) icon size.
    public private(set) var edgeInset: CGFloat = 0
    /// Gap between the material and the screen edge.
    public static let screenGap: CGFloat = 4
    /// Space between neighbouring icon tiles.
    public static let iconSpacing: CGFloat = 4
    /// Proportions measured from the macOS 26 system Dock at 2x (tile ≈ 58 pt): material
    /// padding ≈ 9.9 pt on every side of the tile (0.17 × tile), corner radius ≈ 22 pt
    /// (0.28 × thickness), and a separator slot ≈ 0.43 × tile between the two 4 pt gaps.
    static let insetRatio: CGFloat = 0.17
    static let cornerRatio: CGFloat = 0.28
    static let separatorRatio: CGFloat = 0.43
    /// Material padding around an icon tile, identical on the outer, inner and end sides like
    /// the system Dock. Running indicators sit inside the outer inset and never add thickness.
    public static func edgeInset(for size: CGFloat) -> CGFloat { max(4, size * insetRatio) }
    public static func thickness(for size: CGFloat) -> CGFloat { size + 2 * edgeInset(for: size) }
    public static func cornerRadius(for size: CGFloat) -> CGFloat { thickness(for: size) * cornerRatio }
    /// Indicator centre, measured outward from the tile's outer edge. The system Dock puts the
    /// dot about 6 pt above the material's outer edge, i.e. 0.62 of the inset from the edge.
    public static func indicatorOffset(for size: CGFloat) -> CGFloat { edgeInset(for: size) * 0.38 }
    /// Indicator diameter: about 4 pt on a 58 pt tile, never scaled by magnification.
    public static func indicatorDiameter(for size: CGFloat) -> CGFloat { max(2, min(4, size / 14)) }
    public init(kinds: [DockItem.Kind], bounds: CGRect, position: DockPosition, baseSize: CGFloat,
                maximumSize: CGFloat, pointer: CGPoint? = nil) {
        self.position = position
        guard !kinds.isEmpty else { iconFrames = []; background = .zero; return }
        let horizontal = position == .bottom
        let length = horizontal ? bounds.width : bounds.height
        let base = min(128, max(16, baseSize.isFinite ? baseSize : 48))
        let gap = Self.iconSpacing
        let gaps = CGFloat(max(0, kinds.count - 1)) * gap
        // Fit crowded Docks without putting inaccessible icons offscreen.
        let units = kinds.reduce(CGFloat(0)) { $0 + ($1 == .separator ? Self.separatorRatio : 1) }
        let size = min(base, max(4, (length - 2 * Self.edgeInset(for: base) - gaps) / max(1, units)))
        let inset = Self.edgeInset(for: size)
        edgeInset = inset; iconSize = size
        cornerRadius = Self.cornerRadius(for: size)
        let widths = kinds.map { $0 == .separator ? size * Self.separatorRatio : size }
        let restLength = widths.reduce(0, +) + gaps
        var cursor = (length - restLength) / 2
        let coordinate = pointer.map { horizontal ? $0.x - bounds.minX : bounds.maxY - $0.y }
        let sizes = widths.enumerated().map { index, width -> CGFloat in
            defer { cursor += width + gap }
            guard kinds[index] != .separator, let coordinate else { return width }
            let scale = MagnificationPolicy.scale(distance: Double((coordinate - cursor - width / 2) / size), baseSize: Double(base), maximumSize: Double(maximumSize))
            return width * CGFloat(scale)
        }
        let requested = sizes.reduce(0, +) + gaps
        let fit = min(1, max(1, length - 2 * inset - gaps) / max(1, requested - gaps))
        let total = sizes.reduce(0, +) * fit + gaps
        cursor = (length - total) / 2
        let start = cursor
        let outer = Self.screenGap + inset
        iconFrames = sizes.enumerated().map { index, width in
            let side = width * fit
            defer { cursor += side + gap }
            let depth = kinds[index] == .separator ? size * 0.7 : side
            switch position {
            case .bottom: return CGRect(x: bounds.minX + cursor, y: bounds.minY + outer, width: side, height: depth)
            case .left: return CGRect(x: bounds.minX + outer, y: bounds.maxY - cursor - side, width: depth, height: side)
            case .right: return CGRect(x: bounds.maxX - outer - depth, y: bounds.maxY - cursor - side, width: depth, height: side)
            }
        }
        // The end padding equals the edge inset, so the material is evenly padded all round.
        let screenGap = Self.screenGap, thickness = size + 2 * inset, span = total + 2 * inset
        switch position {
        case .bottom: background = CGRect(x: bounds.minX + start - inset, y: bounds.minY + screenGap, width: span, height: thickness)
        case .left: background = CGRect(x: bounds.minX + screenGap, y: bounds.maxY - start - total - inset, width: thickness, height: span)
        case .right: background = CGRect(x: bounds.maxX - screenGap - thickness, y: bounds.maxY - start - total - inset, width: thickness, height: span)
        }
    }
    /// Separator gaps are reserved for resizing. Without one, use the inward material edge.
    public func resizeHandle(kinds: [DockItem.Kind]) -> CGRect {
        guard !background.isEmpty else { return .zero }
        if let index = kinds.firstIndex(of: .separator), iconFrames.indices.contains(index) {
            let frame = iconFrames[index]
            return position == .bottom ? frame.insetBy(dx: -3, dy: 0) : frame.insetBy(dx: 0, dy: -3)
        }
        // Inside the inward inset, which is only 4 pt at the smallest icon size.
        let depth = min(6, max(1, edgeInset - 2)), margin = min(2, (edgeInset - depth) / 2)
        switch position {
        case .bottom: return CGRect(x: background.midX - 12, y: background.maxY - margin - depth, width: 24, height: depth)
        case .left: return CGRect(x: background.maxX - margin - depth, y: background.midY - 12, width: depth, height: 24)
        case .right: return CGRect(x: background.minX + margin, y: background.midY - 12, width: depth, height: 24)
        }
    }
    /// The inward border also resizes, without stealing input from app icons.
    public var resizeEdge: CGRect {
        guard !background.isEmpty else { return .zero }
        let radius = min(cornerRadius, min(background.width, background.height) / 2)
        // Exactly the inner inset, so the edge never overlaps a resting icon.
        let depth = edgeInset
        switch position {
        case .bottom:
            return CGRect(x: background.minX + radius, y: background.maxY - depth,
                          width: max(0, background.width - radius * 2), height: depth)
        case .left:
            return CGRect(x: background.maxX - depth, y: background.minY + radius,
                          width: depth, height: max(0, background.height - radius * 2))
        case .right:
            return CGRect(x: background.minX, y: background.minY + radius,
                          width: depth, height: max(0, background.height - radius * 2))
        }
    }
    public func containsResizeTarget(_ point: CGPoint, kinds: [DockItem.Kind]) -> Bool {
        resizeHandle(kinds: kinds).contains(point) || resizeEdge.contains(point)
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
