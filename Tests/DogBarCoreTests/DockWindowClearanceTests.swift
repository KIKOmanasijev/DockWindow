import XCTest
@testable import DogBarCore

final class DockWindowClearanceTests: XCTestCase {
    let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    func testMaximizedWindowLeavesBottomDockClear() {
        let result = DockWindowClearance.adjustedFrame(visible, visible: visible, screen: display, edge: .bottom, depth: 80)
        XCTAssertEqual(result, CGRect(x: 0, y: 25, width: 1440, height: 795))
    }
    func testOrdinaryAndAlreadyAdjustedWindowsAreUntouched() {
        XCTAssertNil(DockWindowClearance.adjustedFrame(CGRect(x: 100, y: 100, width: 700, height: 600), visible: visible, screen: display, edge: .bottom, depth: 80))
        XCTAssertNil(DockWindowClearance.adjustedFrame(CGRect(x: 0, y: 25, width: 1440, height: 795), visible: visible, screen: display, edge: .bottom, depth: 80))
    }
    func testSideDocksAndOffsetDisplay() {
        XCTAssertEqual(DockWindowClearance.adjustedFrame(visible, visible: visible, screen: display, edge: .left, depth: 80), CGRect(x: 80, y: 25, width: 1360, height: 875))
        XCTAssertEqual(DockWindowClearance.adjustedFrame(visible, visible: visible, screen: display, edge: .right, depth: 80), CGRect(x: 0, y: 25, width: 1360, height: 875))
        let offset = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        XCTAssertEqual(DockWindowClearance.adjustedFrame(offset, visible: offset, screen: offset, edge: .bottom, depth: 80), CGRect(x: -1440, y: -900, width: 1440, height: 820))
    }
}
