import XCTest
@testable import DogBarCore

@MainActor final class SwitcherModeTests: XCTestCase {
    func testModesPersistAndRespectPreviouslyDisabledSwitcher() {
        let name = "DogBar.SwitcherModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.switcherMode, .windows)
        settings.switcherMode = .apps
        XCTAssertEqual(AppSettings(defaults: defaults).switcherMode, .apps)
        XCTAssertTrue(settings.switcherEnabled)
        settings.switcherMode = .native
        XCTAssertFalse(settings.switcherEnabled)
        settings.switcherMode = .windows
        XCTAssertTrue(settings.switcherEnabled)
        // Older builds stored only switcherEnabled=false. Keep macOS handling their shortcuts.
        defaults.removeObject(forKey: AppSettings.keyPrefix + "switcherMode")
        settings.switcherEnabled = false
        XCTAssertEqual(settings.switcherMode, .native)
        settings.reset()
        XCTAssertEqual(settings.switcherMode, .windows)
    }

    func testApplicationModeIncludesWindowlessAppsOnceAndUsesAppMRU() {
        let older = TrackedApp(pid: 1, name: "Older", lastActivatedAt: Date(timeIntervalSince1970: 1))
        let current = TrackedApp(pid: 2, name: "Current", isFrontmost: true)
        let recent = TrackedApp(pid: 3, name: "Recent", lastActivatedAt: Date(timeIntervalSince1970: 3))
        let hidden = TrackedApp(pid: 4, name: "Hidden", isHidden: true)
        let snapshot = WindowSnapshot(apps: [older, recent, hidden, current])
        let items = SwitcherPolicy.applications(snapshot: snapshot, includeHidden: false)
        XCTAssertEqual(items.map(\.tileID), [.app(2), .app(3), .app(1)])
        XCTAssertEqual(SwitcherPolicy.applications(snapshot: snapshot, includeHidden: true).count, 4)
    }
}
