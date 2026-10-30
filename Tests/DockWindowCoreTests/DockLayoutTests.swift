import XCTest
@testable import DockWindowCore

final class DockLayoutTests: XCTestCase {
    func testRestingBottomGeometryAndTransparentOverflow() {
        let kinds: [DockItem.Kind] = [.application, .application, .separator, .trash]
        let layout = DockLayout(kinds: kinds, bounds: CGRect(x: 0, y: 0, width: 800, height: 210), position: .bottom, baseSize: 48, maximumSize: 96)
        XCTAssertEqual(layout.background.midX, 400, accuracy: 0.001)
        XCTAssertEqual(layout.background.minY, 4)
        XCTAssertEqual(layout.iconFrames[0].width, 48)
        XCTAssertEqual(layout.iconFrames[1].minX - layout.iconFrames[0].maxX, 4)
        XCTAssertEqual(layout.hitTest(CGPoint(x: layout.iconFrames[1].midX, y: 30), kinds: kinds), 1)
        XCTAssertNil(layout.hitTest(CGPoint(x: layout.iconFrames[2].midX, y: 30), kinds: kinds))
        XCTAssertNil(layout.hitTest(CGPoint(x: 400, y: 200), kinds: kinds))
        XCTAssertEqual(layout.insertionIndex(at: CGPoint(x: -100, y: 0)), 0)
        XCTAssertEqual(layout.insertionIndex(at: CGPoint(x: 900, y: 0)), kinds.count)
    }
    func testMagnifiedFramesStayOrderedAndBackgroundGrows() {
        let kinds = Array(repeating: DockItem.Kind.application, count: 9)
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 210)
        let rest = DockLayout(kinds: kinds, bounds: bounds, position: .bottom, baseSize: 48, maximumSize: 96)
        let active = DockLayout(kinds: kinds, bounds: bounds, position: .bottom, baseSize: 48, maximumSize: 96, pointer: CGPoint(x: 600, y: 30))
        XCTAssertEqual(active.iconFrames[4].width, 96, accuracy: 0.001)
        XCTAssertEqual(active.iconFrames[3].width, active.iconFrames[5].width, accuracy: 0.001)
        XCTAssertGreaterThan(active.background.width, rest.background.width)
        XCTAssertEqual(active.background.midX, bounds.midX, accuracy: 0.001)
        XCTAssertTrue(active.containsInteractivePoint(CGPoint(x: active.iconFrames[4].midX, y: active.iconFrames[4].maxY - 1)))
        XCTAssertFalse(active.containsInteractivePoint(CGPoint(x: active.iconFrames[0].midX, y: active.iconFrames[4].maxY - 1)))
        for index in 1..<kinds.count { XCTAssertGreaterThanOrEqual(active.iconFrames[index].minX, active.iconFrames[index - 1].maxX) }
    }
    func testSideDockMirrorsInwardAxisAndHitTests() {
        let kinds: [DockItem.Kind] = [.application, .trash]
        let bounds = CGRect(x: 0, y: 0, width: 210, height: 700)
        let left = DockLayout(kinds: kinds, bounds: bounds, position: .left, baseSize: 48, maximumSize: 96)
        let right = DockLayout(kinds: kinds, bounds: bounds, position: .right, baseSize: 48, maximumSize: 96)
        XCTAssertEqual(left.background.minX, 4)
        XCTAssertEqual(right.background.maxX, bounds.maxX - 4)
        XCTAssertEqual(left.background.midY, 350, accuracy: 0.001)
        XCTAssertEqual(left.iconFrames[0].minX, bounds.maxX - right.iconFrames[0].maxX)
        XCTAssertEqual(right.hitTest(CGPoint(x: right.iconFrames[1].midX, y: right.iconFrames[1].midY), kinds: kinds), 1)
        XCTAssertEqual(right.insertionIndex(at: CGPoint(x: 0, y: bounds.maxY)), 0)
    }
    func testCrowdedMagnificationFitsScreen() {
        let kinds = Array(repeating: DockItem.Kind.application, count: 35)
        let layout = DockLayout(kinds: kinds, bounds: CGRect(x: 0, y: 0, width: 900, height: 210), position: .bottom, baseSize: 48, maximumSize: 128, pointer: CGPoint(x: 450, y: 20))
        XCTAssertGreaterThanOrEqual(layout.background.minX, -0.000001)
        XCTAssertLessThanOrEqual(layout.background.maxX, 900.000001)
        XCTAssertTrue(layout.iconFrames.allSatisfy { $0.width > 0 && $0.minX >= 0 && $0.maxX <= 900 })
    }
    func testRemovalThresholdAndPanelPositionsOnOffsetScreen() {
        let screen = CGRect(x: -1440, y: 300, width: 1440, height: 900)
        for position in DockPosition.allCases {
            let frame = DockLayout.panelFrame(screen: screen, position: position)
            XCTAssertTrue(screen.contains(frame))
            let hidden = DockLayout.hiddenFrame(frame, position: position)
            XCTAssertFalse(screen.intersects(hidden))
        }
        XCTAssertTrue(DockLayout.touchesEdge(CGPoint(x: -1000, y: 301), screen: screen, position: .bottom))
        XCTAssertFalse(DockLayout.touchesEdge(CGPoint(x: 20, y: 301), screen: screen, position: .bottom))
        let layout = DockLayout(kinds: [.application], bounds: CGRect(x: 0, y: 0, width: 800, height: 210), position: .bottom, baseSize: 48, maximumSize: 96)
        XCTAssertFalse(layout.isDragRemoval(at: CGPoint(x: 400, y: layout.background.maxY + 60)))
        XCTAssertTrue(layout.isDragRemoval(at: CGPoint(x: 400, y: layout.background.maxY + 61)))
    }
    func testEmptyDockHasFiniteGeometryAndNoHit() {
        let layout = DockLayout(kinds: [], bounds: CGRect(x: 0, y: 0, width: 800, height: 210), position: .bottom, baseSize: .nan, maximumSize: .infinity)
        XCTAssertTrue(layout.background.width.isFinite)
        XCTAssertNil(layout.hitTest(CGPoint(x: 400, y: 20), kinds: []))
        XCTAssertEqual(layout.insertionIndex(at: .zero), 0)
    }
}
