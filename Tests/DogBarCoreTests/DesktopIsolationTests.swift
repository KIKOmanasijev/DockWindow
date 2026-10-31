import XCTest
@testable import DogBarCore
final class DesktopIsolationTests: XCTestCase {
    func testTargetCannotMoveToAnotherDisplayOrSurviveUnplug() throws {
        let target = try XCTUnwrap(DesktopTarget(spaceID: 9, activeSpaceIDs: ["left": 9, "right": 8]))
        XCTAssertTrue(target.isCurrent(in: ["left": 9, "right": 10]))
        XCTAssertFalse(target.isCurrent(in: ["left": 10, "right": 9]))
        XCTAssertFalse(target.isCurrent(in: ["right": 9]))
        XCTAssertNil(DesktopTarget(spaceID: 0, activeSpaceIDs: ["Main": 0]))
    }
    func testAllDesktopDockStillFocusesLocalWindow() {
        let app = TrackedApp(pid: 7, isFrontmost: false)
        let remote = TrackedWindow(id: 1, pid: 7, spaceIDs: [1], lastFocusedAt: .now)
        let local = TrackedWindow(id: 2, pid: 7, spaceIDs: [2])
        XCTAssertEqual(DockClickPolicy.action(app: app, windows: [remote, local], currentSpaceIDs: [2]), .focus(2))
        XCTAssertEqual(DockClickPolicy.action(app: app, windows: [remote], currentSpaceIDs: [2]), .openNewWindowHere)
    }
    func testFullscreenAndSharedTargets() throws {
        let target = try XCTUnwrap(DesktopTarget(spaceID: 44, activeSpaceIDs: ["Main": 44]))
        XCTAssertTrue(target.isCurrent(in: ["Main": 44]))
        XCTAssertFalse(target.isCurrent(in: ["Main": 1]))
        XCTAssertTrue(SpacePolicy.isOnCurrentSpace(TrackedWindow(id: 3, spaceIDs: [44], isFullscreen: true), currentSpaceIDs: [44]))
    }
}
