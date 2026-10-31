import XCTest
@testable import DogBarCore

final class DockDisplayPushTests: XCTestCase {
    // Main display, and a second display to its right whose bottom sits lower.
    private let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: -200, width: 1920, height: 1080)]
    private let edge = CGPoint(x: 2400, y: -200)

    /// Feeds `count` downward moves of `dy` points, one every 16 ms from `start`.
    private func push(_ state: inout DockDisplayPush, dy: CGFloat, count: Int, start: TimeInterval,
                      at point: CGPoint? = nil, current: Int? = 0) -> Int? {
        var result: Int?
        for i in 0..<count {
            result = state.update(point: point ?? edge, delta: CGVector(dx: 0, dy: dy), time: start + Double(i) * 0.016,
                                  screens: screens, current: current, position: .bottom) ?? result
        }
        return result
    }

    func testADeliberatePushAfterSettlingMovesTheDock() {
        var state = DockDisplayPush()
        XCTAssertNil(push(&state, dy: 0, count: 1, start: 0), "arriving at the edge")
        XCTAssertNil(push(&state, dy: 10, count: 9, start: 0.3), "90 points is not enough")
        XCTAssertEqual(push(&state, dy: 10, count: 1, start: 0.45), 1)
    }

    func testTheOvershootOfAFastMoveToTheEdgeDoesNotCount() {
        var state = DockDisplayPush()
        // A fling to the bottom keeps "pushing" hard for a moment after the pointer stops.
        XCTAssertNil(push(&state, dy: 40, count: 12, start: 0), "480 points within the settle time are ignored")
    }

    func testRestingOrPushingOnTheCurrentDisplayDoesNothing() {
        var state = DockDisplayPush()
        XCTAssertNil(push(&state, dy: 20, count: 40, start: 0, at: CGPoint(x: 700, y: 0)))
        XCTAssertNil(push(&state, dy: 0, count: 60, start: 1), "resting at the edge never moves it")
    }

    func testAPauseStartsThePushOver() {
        var state = DockDisplayPush()
        _ = push(&state, dy: 0, count: 1, start: 0)
        XCTAssertNil(push(&state, dy: 10, count: 8, start: 0.3))
        XCTAssertNil(push(&state, dy: 10, count: 8, start: 1.5), "pushes more than 0.35 s apart do not add up")
    }

    func testSlidingAlongTheEdgeNeitherCountsNorCancels() {
        var state = DockDisplayPush()
        _ = push(&state, dy: 0, count: 1, start: 0)
        XCTAssertNil(push(&state, dy: 10, count: 6, start: 0.3))
        _ = state.update(point: CGPoint(x: 2410, y: -200), delta: CGVector(dx: 10, dy: 0), time: 0.42, screens: screens, current: 0, position: .bottom)
        XCTAssertEqual(push(&state, dy: 10, count: 4, start: 0.44, at: CGPoint(x: 2420, y: -200)), 1)
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
