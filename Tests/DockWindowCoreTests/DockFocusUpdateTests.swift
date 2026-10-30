import XCTest
@testable import DockWindowCore

final class DockFocusUpdateTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 100)
    private func inventory(frontmost: Int32 = 1) -> WindowSnapshot {
        WindowSnapshot(apps: [TrackedApp(pid: 1, isFrontmost: frontmost == 1), TrackedApp(pid: 2, isFrontmost: frontmost == 2)],
                       windows: [TrackedWindow(id: 10, pid: 1, spaceIDs: [7]), TrackedWindow(id: 20, pid: 2, spaceIDs: [7])],
                       activeSpaceIDs: ["Main": 7])
    }
    func testActivationPublishesOverExistingInventoryAndSurvivesStaleScan() {
        var state = DockFocusSnapshotPolicy()
        state.inventory(inventory(), revision: 1)
        let originalWindows = state.snapshot.windows
        state.activate(TrackedApp(pid: 2), at: time)
        XCTAssertEqual(state.snapshot.apps.filter(\.isFrontmost).map(\.pid), [2])
        XCTAssertEqual(state.snapshot.windows, originalWindows)
        state.inventory(inventory(), revision: 2)
        XCTAssertEqual(state.snapshot.apps.filter(\.isFrontmost).map(\.pid), [2])
        XCTAssertEqual(state.snapshot.apps.first { $0.pid == 2 }?.lastActivatedAt, time)
    }
    func testNewActivationAppearsBeforeInventoryAndCanBeRetiredAfterAcknowledgement() {
        var state = DockFocusSnapshotPolicy()
        state.activate(TrackedApp(pid: 3), at: time)
        state.inventory(inventory(), revision: 1)
        XCTAssertEqual(state.snapshot.apps.filter(\.isFrontmost).map(\.pid), [3])
        state.inventory(inventory(), revision: 2, activationRevision: state.activationRevision)
        XCTAssertFalse(state.snapshot.apps.contains { $0.pid == 3 })
    }
    func testFocusReordersMRUAndRejectsOldOrBackgroundEvents() {
        var state = DockFocusSnapshotPolicy()
        state.inventory(inventory(), revision: 1)
        state.activate(TrackedApp(pid: 2), at: time)
        XCTAssertFalse(state.focused(id: 10, pid: 1, at: time.addingTimeInterval(2)))
        XCTAssertFalse(state.focused(id: 20, pid: 2, at: time.addingTimeInterval(-1)))
        XCTAssertTrue(state.focused(id: 20, pid: 2, at: time.addingTimeInterval(1)))
        state.inventory(inventory(), revision: 2)
        XCTAssertEqual(state.snapshot.windows.first?.id, 20)
        XCTAssertEqual(state.snapshot.windows.first?.lastFocusedAt, time.addingTimeInterval(1))
        XCTAssertFalse(state.focused(id: 20, pid: 2, at: time))
    }
    func testFocusForNewWindowSurvivesUntilInventoryDiscoversIt() {
        var state = DockFocusSnapshotPolicy()
        state.inventory(inventory(), revision: 1)
        state.activate(TrackedApp(pid: 2), at: time)
        XCTAssertTrue(state.focused(id: 21, pid: 2, at: time))
        var next = inventory()
        next.windows.append(TrackedWindow(id: 21, pid: 2))
        state.inventory(next, revision: 2)
        XCTAssertEqual(state.snapshot.windows.first?.id, 21)
    }
    func testSpacePublicationSurvivesScanAndRejectsMismatchedMembershipRevision() {
        var state = DockFocusSnapshotPolicy()
        state.inventory(inventory(), revision: 1)
        state.spaces(["Main": 8], membership: [20: [8]], revision: 1)
        state.inventory(inventory(), revision: 2)
        XCTAssertEqual(state.snapshot.activeSpaceID, 8)
        XCTAssertEqual(state.snapshot.windows.first { $0.id == 20 }?.spaceIDs, [8])
        state.spaces(["Main": 9], membership: [20: [9]], revision: 1)
        XCTAssertEqual(state.snapshot.activeSpaceID, 9)
        XCTAssertEqual(state.snapshot.windows.first { $0.id == 20 }?.spaceIDs, [8])
        state.spaces(["Main": 9], membership: [20: []], revision: 2)
        XCTAssertEqual(state.snapshot.windows.first { $0.id == 20 }?.rememberedSpaceIDs, [8])
    }
    func testMembershipDoesNotMoveMinimizedWindowsOrResurrectRemovedWindows() {
        var state = DockFocusSnapshotPolicy()
        var next = inventory()
        next.windows[0].isMinimized = true
        state.inventory(next, revision: 1)
        state.spaces(["Main": 8], membership: [10: [8], 20: [8]], revision: 1)
        XCTAssertEqual(state.snapshot.windows.first { $0.id == 10 }?.spaceIDs, [7])
        next.windows.removeAll { $0.id == 20 }
        state.inventory(next, revision: 2)
        XCTAssertFalse(state.snapshot.windows.contains { $0.id == 20 })
        state.inventory(inventory(), revision: 1)
        XCTAssertFalse(state.snapshot.windows.contains { $0.id == 20 })
    }
    func testMultipleFocusEventsRetainMRUAcrossStaleInventory() {
        var state = DockFocusSnapshotPolicy()
        var next = inventory()
        next.windows.append(TrackedWindow(id: 11, pid: 1))
        state.inventory(next, revision: 1)
        XCTAssertTrue(state.focused(id: 11, pid: 1, at: time))
        XCTAssertTrue(state.focused(id: 10, pid: 1, at: time.addingTimeInterval(1)))
        state.inventory(next, revision: 2)
        XCTAssertEqual(state.snapshot.windows.map(\.id), [10, 11, 20])
        XCTAssertEqual(state.snapshot.windows[1].lastFocusedAt, time)
    }
    func testSlowMembershipCannotRollBackNewerEventTopology() {
        var state = DockFocusSnapshotPolicy()
        state.inventory(inventory(), revision: 1)
        state.spaces(["Main": 8], at: time.addingTimeInterval(1))
        state.spaces(["Main": 7], membership: [20: [7]], revision: 1, at: time)
        XCTAssertEqual(state.snapshot.activeSpaceID, 8)
    }
    func testAccessoryActivationClearsIndicatorWithoutAddingDockApp() {
        var state = DockFocusSnapshotPolicy()
        state.inventory(inventory(), revision: 1)
        state.activate(TrackedApp(pid: 3), at: time, includeInInventory: false)
        XCTAssertTrue(state.snapshot.apps.filter(\.isFrontmost).isEmpty)
        XCTAssertEqual(state.snapshot.apps.map(\.pid), [1, 2])
    }
}
