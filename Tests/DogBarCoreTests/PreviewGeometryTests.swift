import XCTest
@testable import DogBarCore

final class PreviewGeometryTests: XCTestCase {
    func testBottomCentersAboveAnchor() {
        let frame = PreviewGeometry.frame(size: CGSize(width: 300, height: 200), anchor: CGRect(x: 480, y: 0, width: 40, height: 50), bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), edge: .bottom)
        XCTAssertEqual(frame, CGRect(x: 350, y: 60, width: 300, height: 200))
    }
    func testSideEdgesFaceInterior() {
        let bounds = CGRect(x: -1440, y: -300, width: 1440, height: 900)
        let size = CGSize(width: 320, height: 220)
        let left = PreviewGeometry.frame(size: size, anchor: CGRect(x: -1440, y: 100, width: 60, height: 60), bounds: bounds, edge: .left)
        let right = PreviewGeometry.frame(size: size, anchor: CGRect(x: -60, y: 100, width: 60, height: 60), bounds: bounds, edge: .right)
        XCTAssertEqual(left.minX, -1370)
        XCTAssertEqual(right.maxX, -70)
        XCTAssertEqual(left.midY, 130)
        XCTAssertEqual(right.midY, 130)
    }
    func testClampEveryEdgeAndOversizedPanel() {
        let bounds = CGRect(x: -900, y: -500, width: 900, height: 600)
        for edge in [DockPosition.bottom, .left, .right] {
            for anchor in [CGRect(x: -910, y: -510, width: 40, height: 40), CGRect(x: -10, y: 90, width: 40, height: 40)] {
                let frame = PreviewGeometry.frame(size: CGSize(width: 300, height: 200), anchor: anchor, bounds: bounds, edge: edge)
                XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX)
                XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY)
                XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX)
                XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY)
                XCTAssertEqual(PreviewGeometry.frame(size: CGSize(width: 2000, height: 2000), anchor: anchor, bounds: bounds, edge: edge), bounds)
            }
        }
    }
    func testNativeEdgeInferenceWithOffsetDisplay() {
        let screen = CGRect(x: -1600, y: 900, width: 1600, height: 1000)
        XCTAssertEqual(PreviewGeometry.edge(anchor: CGRect(x: -900, y: 900, width: 60, height: 60), screen: screen), .bottom)
        XCTAssertEqual(PreviewGeometry.edge(anchor: CGRect(x: -1600, y: 1300, width: 60, height: 60), screen: screen), .left)
        XCTAssertEqual(PreviewGeometry.edge(anchor: CGRect(x: -60, y: 1300, width: 60, height: 60), screen: screen), .right)
    }
    func testBridgeAcrossAllEdges() {
        let anchor = CGRect(x: 100, y: 100, width: 40, height: 40)
        let examples: [(DockPosition, CGRect, CGPoint)] = [
            (.bottom, CGRect(x: 0, y: 170, width: 300, height: 200), CGPoint(x: 120, y: 155)),
            (.left, CGRect(x: 170, y: 0, width: 300, height: 240), CGPoint(x: 155, y: 120)),
            (.right, CGRect(x: -230, y: 0, width: 300, height: 240), CGPoint(x: 85, y: 120))
        ]
        for (edge, panel, point) in examples {
            XCTAssertTrue(PreviewGeometry.bridgeContains(point, anchor: anchor, panel: panel, edge: edge))
            XCTAssertTrue(PreviewGeometry.bridgeContains(CGPoint(x: 120, y: 120), anchor: anchor, panel: panel, edge: edge))
            XCTAssertTrue(PreviewGeometry.bridgeContains(CGPoint(x: panel.midX, y: panel.midY), anchor: anchor, panel: panel, edge: edge))
            XCTAssertFalse(PreviewGeometry.bridgeContains(CGPoint(x: 900, y: 900), anchor: anchor, panel: panel, edge: edge))
        }
    }
    func testBridgeTapersAndTranslationPreservesPoints() {
        let anchor = CGRect(x: 100, y: 0, width: 40, height: 40)
        let panel = CGRect(x: 0, y: 100, width: 300, height: 200)
        XCTAssertFalse(PreviewGeometry.bridgeContains(CGPoint(x: 0, y: 50), anchor: anchor, panel: panel, edge: .bottom, tolerance: 0))
        let offset = CGVector(dx: -1600, dy: 800)
        for point in [CGPoint(x: 120, y: 60), CGPoint(x: 0, y: 50), CGPoint(x: 250, y: 200)] {
            XCTAssertEqual(PreviewGeometry.bridgeContains(point, anchor: anchor, panel: panel, edge: .bottom),
                           PreviewGeometry.bridgeContains(CGPoint(x: point.x + offset.dx, y: point.y + offset.dy), anchor: anchor.offsetBy(dx: offset.dx, dy: offset.dy), panel: panel.offsetBy(dx: offset.dx, dy: offset.dy), edge: .bottom))
        }
    }
}
