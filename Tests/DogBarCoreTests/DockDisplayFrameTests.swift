import XCTest
@testable import DogBarCore

final class DockDisplayFrameTests: XCTestCase {
    func testCurrentDisplayRemainsRestrictedWhenIncludingAllDesktops() {
        let local = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let app = TrackedApp(pid: 42, bundleIdentifier: "test.remote", name: "Remote")
        let remote = TrackedWindow(id: 1, pid: 42, frame: CGRect(x: 1200, y: 100, width: 300, height: 200), spaceIDs: [2])
        let snapshot = WindowSnapshot(apps: [app], windows: [remote])
        let options = DockCompositionOptions(scope: .allDesktops, currentSpaceIDs: [1], displayFrame: local)
        XCTAssertFalse(DockCompositionPolicy.items(snapshot: snapshot, pinned: [], options: options).contains { $0.app?.pid == 42 })
        XCTAssertEqual(DotPolicy.indicators(windows: [remote], filter: WindowFilter(scope: .allDesktops, displayFrame: local)).count, 0)
        let all = DockCompositionOptions(scope: .allDesktops, currentSpaceIDs: [1])
        XCTAssertTrue(DockCompositionPolicy.items(snapshot: snapshot, pinned: [], options: all).contains { $0.app?.pid == 42 })
    }
}
