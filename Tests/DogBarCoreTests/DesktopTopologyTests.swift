import XCTest
@testable import DogBarCore

final class DesktopTopologyTests: XCTestCase {
    func testLiveDisplaySpaceWinsOverCopiedTopologyDuringTransition() {
        XCTAssertEqual(DesktopTopologyPolicy.currentSpace(reported: 1, live: 2, known: [1, 2]), 2)
        // A cancelled/reversed swipe returns to the original desktop immediately.
        XCTAssertEqual(DesktopTopologyPolicy.currentSpace(reported: 2, live: 1, known: [1, 2]), 1)
    }
    func testUnavailableAndForeignDisplayResultsUseTopologyFallback() {
        for live: UInt64? in [nil, 0, 99] {
            XCTAssertEqual(DesktopTopologyPolicy.currentSpace(reported: 1, live: live, known: [1, 2]), 1)
        }
        XCTAssertNil(DesktopTopologyPolicy.currentSpace(reported: nil, live: 99, known: [1, 2]))
        XCTAssertEqual(DesktopTopologyPolicy.currentSpace(reported: 1, live: 3, known: [1, 2, 3]), 3)
    }
}
