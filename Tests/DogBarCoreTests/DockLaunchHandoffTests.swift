import XCTest
@testable import DogBarCore

final class DockLaunchHandoffTests: XCTestCase {
    func testWindowDiscoveryDoesNotRetireLaunchBeforeDesktopDiscovery() {
        var snapshot = WindowSnapshot(apps: [TrackedApp(pid: 42)], windows: [TrackedWindow(id: 10, pid: 42)])
        XCTAssertFalse(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: true))
        snapshot.windows[0].spaceIDs = [1]
        XCTAssertTrue(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: true))
    }
    func testAllDesktopScopeDoesNotRequireMembershipButStillRequiresAppAndWindow() {
        var snapshot = WindowSnapshot(windows: [TrackedWindow(id: 10, pid: 42)])
        XCTAssertFalse(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: false))
        snapshot.apps = [TrackedApp(pid: 42)]
        XCTAssertTrue(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: false))
        snapshot.windows = []
        XCTAssertFalse(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: false))
    }
}
