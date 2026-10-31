import XCTest
@testable import DogBarCore

@MainActor final class PreviewOptionsTests: XCTestCase {
    func testPreviewAndWindowlessDefaultsAndPersistence() {
        let name = "DogBar.PreviewOptionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.previewShowNewWindowTile)
        XCTAssertFalse(settings.previewShowCPUUsage)
        XCTAssertFalse(settings.previewShowMemoryUsage)
        XCTAssertFalse(settings.switcherShowWindowlessApps)
        settings.previewShowNewWindowTile = false
        settings.previewShowCPUUsage = true
        settings.previewShowMemoryUsage = true
        settings.switcherShowWindowlessApps = true
        let saved = AppSettings(defaults: defaults)
        XCTAssertFalse(saved.previewShowNewWindowTile)
        XCTAssertTrue(saved.previewShowCPUUsage)
        XCTAssertTrue(saved.previewShowMemoryUsage)
        XCTAssertTrue(saved.switcherShowWindowlessApps)
        saved.reset()
        XCTAssertTrue(saved.previewShowNewWindowTile)
        XCTAssertFalse(saved.previewShowCPUUsage)
        XCTAssertFalse(saved.previewShowMemoryUsage)
        XCTAssertFalse(saved.switcherShowWindowlessApps)
    }
}
