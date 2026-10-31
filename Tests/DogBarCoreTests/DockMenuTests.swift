import AppKit
import XCTest
@testable import DogBarCore

final class DockMenuTests: XCTestCase {
    @MainActor func testSelectionRunsOnlyAfterMenuTrackingFinishesAndOnlyOnce() {
        let session = DockMenuSession()
        var tracking = true
        var calls = 0
        session.select {
            XCTAssertFalse(tracking)
            calls += 1
        }
        XCTAssertEqual(calls, 0)
        tracking = false
        session.finish()
        session.finish()
        XCTAssertEqual(calls, 1)
    }

    @MainActor func testCancelledMenuDoesNotRunAnAction() {
        let session = DockMenuSession()
        session.finish()
        var calls = 0
        session.select { calls += 1 }
        XCTAssertEqual(calls, 0)
    }

    @MainActor func testMenuCancelsDelayedPreviewAndBlocksReentrantAndPinnedRequests() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let suite = "DogBar.MenuTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.previewHoverDelay = 0.1
        settings.previewShowEmptyApps = true
        let tracker = WindowTracker()
        let previews = PreviewController(tracker: tracker, actions: WindowActions(tracker: tracker),
            thumbnails: ThumbnailService(), settings: settings, newWindowOpener: NewWindowOpener(tracker: tracker))
        defer { previews.dismiss() }
        previews.enabled = true
        let item = DockItem(id: "fixture", app: TrackedApp(pid: 1, name: "Fixture"))
        let anchor = CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 48, height: 48))
        previews.hover(item: item, anchor: anchor, screen: screen)
        previews.contextMenuTracking = true
        previews.hover(item: item, anchor: anchor, screen: screen)
        previews.showWindows(item: item, anchor: anchor, screen: screen)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(previews.isVisible)

        previews.contextMenuTracking = false
        previews.showWindows(item: item, anchor: anchor, screen: screen)
        XCTAssertTrue(previews.isVisible)
        // Dismissing a visible preview notifies the Dock, which can re-enter hover.
        previews.onVisibilityChanged = { [weak previews] visible in
            if !visible { previews?.hover(item: item, anchor: anchor, screen: screen) }
        }
        previews.contextMenuTracking = true
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(previews.isVisible)
    }
}
