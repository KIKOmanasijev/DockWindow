import XCTest
@testable import DogBarCore

@MainActor final class DesktopPinsTests: XCTestCase {
    private func pin(_ name: String) -> PinnedApp { PinnedApp(bundleIdentifier: name, url: URL(fileURLWithPath: "/Applications/\(name).app")) }
    func testMigrationCopiesAllExistingDesktopsAndEditsStayIndependent() throws {
        let name = "DogBar.DesktopPinsTests.\(UUID())", finder = DockCompositionPolicy.finderBundleIdentifier
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = try PropertyListEncoder().encode([pin("A"), pin("B")])
        defaults.set(legacy, forKey: "pinnedApps.v1")
        let store = PinnedAppsStore(defaults: defaults)
        store.activateDesktop(nil, knownDesktopKeys: ["one", "two"])
        XCTAssertNotNil(defaults.data(forKey: "desktopPins.v2"))
        XCTAssertFalse(store.canEdit)
        store.activateDesktop("one", knownDesktopKeys: ["one", "two"])
        XCTAssertEqual(store.apps.map(\.bundleIdentifier), [finder, "A", "B"])
        store.unpin(bundleIdentifier: finder)
        store.move(from: 1, to: 0)
        XCTAssertEqual(store.apps.map(\.bundleIdentifier), ["B", "A"])
        store.activateDesktop("two", knownDesktopKeys: ["one", "two"])
        XCTAssertEqual(store.apps.map(\.bundleIdentifier), [finder, "A", "B"])
        store.activateDesktop("one", knownDesktopKeys: ["one", "two"])
        // A newly discovered desktop copies the current edited profile exactly once.
        store.activateDesktop("three", knownDesktopKeys: ["one", "two", "three"])
        XCTAssertEqual(store.apps.map(\.bundleIdentifier), ["B", "A"])
        store.unpin(bundleIdentifier: "A")
        store.activateDesktop("one", knownDesktopKeys: ["one", "two", "three"])
        XCTAssertEqual(store.apps.map(\.bundleIdentifier), ["B", "A"])
        let restored = PinnedAppsStore(defaults: defaults)
        restored.activateDesktop("three", knownDesktopKeys: ["one", "two", "three"])
        XCTAssertEqual(restored.apps.map(\.bundleIdentifier), ["B"])
        restored.activateDesktop(nil, knownDesktopKeys: [])
        restored.unpin(bundleIdentifier: "B")
        XCTAssertEqual(restored.apps.map(\.bundleIdentifier), ["B"])
        XCTAssertEqual(defaults.data(forKey: "pinnedApps.v1"), legacy)
    }
    func testFinderIsNotForcedAndPinOrderIsRespected() {
        let items = DockCompositionPolicy.items(snapshot: .init(), pinned: [pin("A"), pin(DockCompositionPolicy.finderBundleIdentifier)], options: .init(showTrash: false))
        XCTAssertEqual(items.map(\.id), ["A", DockCompositionPolicy.finderBundleIdentifier])
        XCTAssertTrue(DockCompositionPolicy.items(snapshot: .init(), pinned: [], options: .init(showTrash: false)).isEmpty)
    }
    func testSpaceIdentitySurvivesReorderingDisplayMovesAndUsesSafeAmbiguousFallback() {
        let a: [String: Any] = ["ManagedSpaceID": 1, "type": 0, "uuid": "ABC"]
        let b: [String: Any] = ["ManagedSpaceID": 2, "type": 0, "uuid": ""]
        let before = DesktopIdentityPolicy.keys(displays: [["Display Identifier": "screenA", "Spaces": [a, b]]], session: "first")
        let after = DesktopIdentityPolicy.keys(displays: [["Display Identifier": "screenB", "Spaces": [b, a]]], session: "next")
        XCTAssertEqual(before, after)
        XCTAssertEqual(before[1], "space:abc")
        XCTAssertEqual(before[2], "system-default")
        let ambiguous = DesktopIdentityPolicy.keys(displays: [["Display Identifier": "screenA", "Spaces": [b, ["ManagedSpaceID": 3, "type": 0]]]], session: "first")
        XCTAssertNotEqual(ambiguous[2], ambiguous[3])
        let restarted = DesktopIdentityPolicy.keys(displays: [["Display Identifier": "screenA", "Spaces": [b, ["ManagedSpaceID": 3, "type": 0]]]], session: "next")
        XCTAssertNotEqual(ambiguous[2], restarted[2])
    }
    func testDesktopCatalogSurvivesInventoryPublications() {
        var state = DockFocusSnapshotPolicy()
        state.spaces(["Main": 1], desktopKeys: [1: "one", 2: "two"])
        state.inventory(WindowSnapshot(activeSpaceIDs: ["Main": 1]), revision: 1)
        XCTAssertEqual(state.snapshot.desktopKeys, [1: "one", 2: "two"])
    }
}
