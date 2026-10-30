import Foundation

/// Scales the entire switcher card, including its header and padding, by ten percent.
enum SwitcherTileMetrics {
    static let scale: CGFloat = 0.9
    static func size(thumbnail: CGSize) -> CGSize {
        CGSize(width: (thumbnail.width + 16) * scale, height: (thumbnail.height + 64) * scale)
    }
}
