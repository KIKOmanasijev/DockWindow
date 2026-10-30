import XCTest
@testable import DockWindowCore

final class SwitcherLayoutTests: XCTestCase {
    func testTileIncludesHeaderSpacingAndPaddingBeforeScaling() {
        for thumbnail in [CGSize(width: 64, height: 48), CGSize(width: 320, height: 200), CGSize(width: 600, height: 400)] {
            let unscaled = SwitcherTileMetrics.unscaledSize(thumbnail: thumbnail)
            XCTAssertEqual(unscaled.width, thumbnail.width + 16)
            XCTAssertEqual(unscaled.height, thumbnail.height + 40 + 8 + 16)
            let scaled = SwitcherTileMetrics.size(thumbnail: thumbnail)
            XCTAssertEqual(scaled.width, unscaled.width * 0.9, accuracy: 0.001)
            XCTAssertEqual(scaled.height, unscaled.height * 0.9, accuracy: 0.001)
        }
    }
    func testColumnsRespectPaddingAndActualScaledWidthAtThreshold() {
        let tile = SwitcherTileMetrics.size(thumbnail: CGSize(width: 320, height: 200))
        let exact = tile.width * 3 + SwitcherTileMetrics.spacing * 2 + SwitcherTileMetrics.padding * 2
        XCTAssertEqual(SwitcherTileMetrics.columns(availableWidth: exact, tileWidth: tile.width, itemCount: 10, maximum: 10), 3)
        XCTAssertEqual(SwitcherTileMetrics.columns(availableWidth: exact - 1, tileWidth: tile.width, itemCount: 10, maximum: 10), 2)
        XCTAssertEqual(SwitcherTileMetrics.columns(availableWidth: exact, tileWidth: tile.width, itemCount: 2, maximum: 10), 2)
        XCTAssertEqual(SwitcherTileMetrics.columns(availableWidth: exact, tileWidth: tile.width, itemCount: 10, maximum: 1), 1)
        XCTAssertEqual(SwitcherTileMetrics.columns(availableWidth: 0, tileWidth: tile.width, itemCount: 0, maximum: 0), 1)
    }
}
