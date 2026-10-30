import XCTest
@testable import DockWindowCore
final class SwitcherSessionTests: XCTestCase {
    private func items(_ ids: [UInt32]) -> [SwitcherItem] { ids.map { .window(TrackedWindow(id: $0)) } }
    func testInitialSelectionAndWrap() {
        var session = SwitcherSession()
        session.begin(items: [], reverse: false); XCTAssertNil(session.selectedID)
        session.begin(items: items([1]), reverse: false); XCTAssertEqual(session.selectedID, .window(1))
        session.begin(items: items([1, 2, 3]), reverse: false); XCTAssertEqual(session.selectedID, .window(2))
        session.begin(items: items([1, 2, 3]), reverse: true); XCTAssertEqual(session.selectedID, .window(3))
        session.move(delta: 1); XCTAssertEqual(session.selectedID, .window(1))
        session.move(delta: -1); XCTAssertEqual(session.selectedID, .window(3))
    }
    func testStableSelectionAndRemoval() {
        var session = SwitcherSession(); session.begin(items: items([1, 2, 3]), reverse: false)
        session.update(items: items([2, 1, 3])); XCTAssertEqual(session.selectedID, .window(2))
        session.update(items: items([1, 3])); XCTAssertEqual(session.selectedID, .window(1))
        session.select(.window(3)); session.update(items: items([1])); XCTAssertEqual(session.selectedID, .window(1))
        session.update(items: []); XCTAssertNil(session.selectedItem)
    }
    func testVerticalNavigationPartialRow() {
        var session = SwitcherSession(); session.begin(items: items([1, 2, 3, 4, 5]), reverse: false)
        session.moveVertically(direction: 1, columns: 3); XCTAssertEqual(session.selectedID, .window(5))
        session.moveVertically(direction: 1, columns: 3); XCTAssertEqual(session.selectedID, .window(2))
    }
    func testMouseEndRetainsKeyUpOwnership() {
        var state = HotkeySessionState(); let config = HotkeyConfiguration()
        _ = state.process(kind: .keyDown, keyCode: 48, flags: .command, configuration: config, canDeliver: true)
        state.endSession(); XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.process(kind: .keyUp, keyCode: 48, configuration: config, canDeliver: true).swallow)
        XCTAssertFalse(state.process(kind: .keyDown, keyCode: 13, flags: .command, configuration: config, canDeliver: true).swallow)
    }
}
