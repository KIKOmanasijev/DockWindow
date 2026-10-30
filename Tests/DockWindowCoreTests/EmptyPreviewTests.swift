import AppKit
import XCTest
@testable import DockWindowCore

final class EmptyPreviewTests: XCTestCase {
    @MainActor func testEmptyHoverIsOffByDefaultForBothDocks() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let suite = "DogBar.EmptyPreview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.previewShowEmptyApps)
        settings.previewHoverDelay = 0
        let tracker = WindowTracker()
        let previews = PreviewController(tracker: tracker, actions: WindowActions(tracker: tracker),
            thumbnails: ThumbnailService(), settings: settings, newWindowOpener: NewWindowOpener(tracker: tracker))
        defer { previews.dismiss() }
        previews.enabled = true
        let anchor = CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 48, height: 48))
        previews.hover(item: DockItem(id: "fixture", app: nil), anchor: anchor, screen: screen)
        XCTAssertFalse(previews.isVisible)
        settings.useDockWindowDock = false
        let native = NativeDockItem(title: "Fixture", bundleIdentifier: nil, bundleURL: nil, badgeLabel: nil, frame: anchor)
        previews.hover(item: native, screen: screen)
        XCTAssertFalse(previews.isVisible)
    }

    @MainActor func testOptInShowsHoverAndDisablingItClosesThePanel() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let suite = "DogBar.EmptyPreviewOptIn.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.previewHoverDelay = 0
        settings.previewShowEmptyApps = true
        let tracker = WindowTracker()
        let previews = PreviewController(tracker: tracker, actions: WindowActions(tracker: tracker),
            thumbnails: ThumbnailService(), settings: settings, newWindowOpener: NewWindowOpener(tracker: tracker))
        defer { previews.dismiss() }
        previews.enabled = true
        let item = DockItem(id: "fixture", app: nil)
        let anchor = CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 48, height: 48))
        previews.hover(item: item, anchor: anchor, screen: screen)
        XCTAssertTrue(previews.isVisible)
        settings.previewShowEmptyApps = false
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(previews.isVisible)
        // Explicit Show All Windows is still allowed to explain an empty result.
        previews.showWindows(item: item, anchor: anchor, screen: screen)
        XCTAssertTrue(previews.isVisible)
    }

    @MainActor func testEmptyPreviewPreferencePersistsAndResetRestoresOff() throws {
        let suite = "DogBar.EmptyPreviewPersistence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.previewShowEmptyApps = true
        XCTAssertTrue(AppSettings(defaults: defaults).previewShowEmptyApps)
        settings.reset()
        XCTAssertFalse(settings.previewShowEmptyApps)
    }
}
