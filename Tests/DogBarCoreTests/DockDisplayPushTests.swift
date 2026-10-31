import XCTest
@testable import DogBarCore

final class DockDisplayPushTests: XCTestCase {
    // Main display, and a second display to its right whose bottom sits lower.
    private let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: -200, width: 1920, height: 1080)]

    private func push(_ push: inout DockDisplayPush, at point: CGPoint, dy: CGFloat, times: Int, start: TimeInterval = 0,
                      step: TimeInterval = 0.016, current: Int? = 0) -> Int? {
        var result: Int?
        for i in 0..<times {
            result = push.update(point: point, delta: CGVector(dx: 0, dy: dy), time: start + Double(i) * step,
                                 screens: screens, current: current, position: .bottom) ?? result
        }
        return result
    }

    func testPushingDownAtAnotherDisplaysBottomEdgeMovesTheDock() {
        var state = DockDisplayPush()
        XCTAssertNil(push(&state, at: CGPoint(x: 2400, y: -200), dy: 8, times: 3), "24 points is not yet a deliberate push")
        XCTAssertEqual(push(&state, at: CGPoint(x: 2400, y: -200), dy: 8, times: 1, start: 0.05), 1)
    }

    func testRestingOrPushingOnTheCurrentDisplayDoesNothing() {
        var state = DockDisplayPush()
        XCTAssertNil(push(&state, at: CGPoint(x: 700, y: 0), dy: 10, times: 10))
        XCTAssertNil(push(&state, at: CGPoint(x: 2400, y: -200), dy: 0, times: 50), "resting at the edge never moves it")
    }

    func testAPauseStartsThePushOver() {
        var state = DockDisplayPush()
        XCTAssertNil(push(&state, at: CGPoint(x: 2400, y: -200), dy: 8, times: 3))
        XCTAssertNil(push(&state, at: CGPoint(x: 2400, y: -200), dy: 8, times: 3, start: 1), "pushes 1 s apart do not add up")
    }

    func testSlidingAlongTheEdgeNeitherCountsNorCancels() {
        var state = DockDisplayPush()
        XCTAssertNil(push(&state, at: CGPoint(x: 2400, y: -200), dy: 8, times: 2))
        _ = state.update(point: CGPoint(x: 2410, y: -200), delta: CGVector(dx: 10, dy: 0), time: 0.05, screens: screens, current: 0, position: .bottom)
        XCTAssertEqual(push(&state, at: CGPoint(x: 2420, y: -200), dy: 8, times: 2, start: 0.07), 1)
    }

    func testAnEdgeSharedWithAnotherDisplayIsNotAnEdge() {
        // A display directly below the main one: the pointer crosses over instead of pushing.
        let stacked = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 0, y: -1080, width: 1920, height: 1080)]
        XCTAssertNil(DockDisplayPush.outerEdgeScreen(point: CGPoint(x: 700, y: 0), screens: stacked, position: .bottom))
        XCTAssertEqual(DockDisplayPush.outerEdgeScreen(point: CGPoint(x: 700, y: -1080), screens: stacked, position: .bottom), 1)
    }

    func testSideDocksPushOutwards() {
        XCTAssertEqual(DockDisplayPush.pushDistance(CGVector(dx: -5, dy: 0), position: .left), 5)
        XCTAssertEqual(DockDisplayPush.pushDistance(CGVector(dx: 5, dy: 0), position: .right), 5)
        XCTAssertEqual(DockDisplayPush.outerEdgeScreen(point: CGPoint(x: 3431, y: 300), screens: screens, position: .right), 1)
        XCTAssertNil(DockDisplayPush.outerEdgeScreen(point: CGPoint(x: 1511, y: 300), screens: screens, position: .right),
                     "the main display's right edge borders the second display")
    }
}
