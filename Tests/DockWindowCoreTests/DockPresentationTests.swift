import AppKit
import XCTest
@testable import DockWindowCore

final class DockPresentationTests: XCTestCase {
    func testSwitcherScalesWholeCardByTenPercentForDefaultAndCustomSizes() {
        for thumbnail in [CGSize(width: 320, height: 200), CGSize(width: 480, height: 300)] {
            let tile = SwitcherTileMetrics.size(thumbnail: thumbnail)
            XCTAssertEqual(tile.width / (thumbnail.width + 16), 0.9, accuracy: 0.0001)
            XCTAssertEqual(tile.height / (thumbnail.height + 64), 0.9, accuracy: 0.0001)
        }
    }

    func testFixedDockGeometryDoesNotGrowOrMoveWhenPointerCrossesIcons() {
        for position in DockPosition.allCases {
            let kinds: [DockItem.Kind] = [.application, .application, .separator, .trash]
            let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
            let rest = DockLayout(kinds: kinds, bounds: bounds, position: position, baseSize: 48, maximumSize: 48)
            for frame in rest.iconFrames {
                let hover = DockLayout(kinds: kinds, bounds: bounds, position: position, baseSize: 48, maximumSize: 48,
                                       pointer: CGPoint(x: frame.midX, y: frame.midY))
                XCTAssertEqual(hover.iconFrames, rest.iconFrames)
                XCTAssertEqual(hover.background, rest.background)
            }
        }
    }

    func testRasterizerSelectsRetinaRepresentationAndProducesPhysicalPixels() async throws {
        try await MainActor.run {
            let image = NSImage(size: NSSize(width: 32, height: 32))
            image.addRepresentation(try bitmap(pixels: 32, color: .red))
            image.addRepresentation(try bitmap(pixels: 64, color: .blue))
            let rendered = try XCTUnwrap(DockIconRasterizer.render(image, size: CGSize(width: 32, height: 32), scale: 2))
            XCTAssertEqual(rendered.width, 64)
            XCTAssertEqual(rendered.height, 64)
            let data = try XCTUnwrap(rendered.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
            let center = 32 * rendered.bytesPerRow + 32 * 4
            XCTAssertGreaterThan(bytes[center + 2], bytes[center], "Retina drawing must choose the blue 2x representation, not upscale the red 1x bitmap.")
        }
    }

    func testLayerRerendersSameImageWhenBackingScaleOrSizeChangesAndClearsMissingImage() async throws {
        try await MainActor.run {
            let image = NSImage(size: NSSize(width: 32, height: 32))
            image.addRepresentation(try bitmap(pixels: 256, color: .blue))
            let layer = DockIconLayer()
            layer.bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
            @MainActor func update(_ image: NSImage?, scale: CGFloat) {
                layer.update(image: image, badgeText: nil, indicators: .init(count: 0), color: .white,
                             position: .bottom, scale: scale, reduceMotion: true)
            }
            @MainActor func renderedWidth() throws -> Int {
                let contents = try XCTUnwrap(layer.imageLayer.contents)
                guard CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
                    XCTFail("The icon layer must contain a CGImage")
                    return 0
                }
                return unsafeBitCast(contents as AnyObject, to: CGImage.self).width
            }
            update(image, scale: 2)
            XCTAssertEqual(try renderedWidth(), 96)
            update(image, scale: 1)
            XCTAssertEqual(try renderedWidth(), 48)
            layer.bounds.size = CGSize(width: 72, height: 72)
            update(image, scale: 2)
            XCTAssertEqual(try renderedWidth(), 144)
            update(nil, scale: 2)
            XCTAssertNil(layer.imageLayer.contents)
        }
    }

    @MainActor private func bitmap(pixels: Int, color: NSColor) throws -> NSBitmapImageRep {
        let representation = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        representation.size = NSSize(width: 32, height: 32)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: representation))
        context.cgContext.setFillColor(color.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return representation
    }
}
