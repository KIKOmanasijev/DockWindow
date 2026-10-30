import Foundation

/// Scales the entire switcher card, including its header and padding, by ten percent.
enum SwitcherTileMetrics {
    static let scale: CGFloat = 0.9
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 20
    static func unscaledSize(thumbnail: CGSize) -> CGSize {
        CGSize(width: thumbnail.width + 16, height: thumbnail.height + 64)
    }
    static func size(thumbnail: CGSize) -> CGSize {
        let unscaled = unscaledSize(thumbnail: thumbnail)
        return CGSize(width: unscaled.width * scale, height: unscaled.height * scale)
    }
    static func columns(availableWidth: CGFloat, tileWidth: CGFloat, itemCount: Int, maximum: Int) -> Int {
        max(1, min(max(1, maximum), max(1, itemCount),
                   Int(max(0, availableWidth - 2 * padding + spacing) / (tileWidth + spacing))))
    }
}
