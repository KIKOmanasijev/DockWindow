import XCTest
@testable import DockWindowCore

final class UIHardeningTests: XCTestCase {
    func testInitialPermissionCheckIsNotReportedAsMissing() {
        XCTAssertEqual(PermissionRowStatus(hasChecked: false, granted: false), .checking)
        XCTAssertEqual(PermissionRowStatus(hasChecked: true, granted: true), .granted)
        XCTAssertEqual(PermissionRowStatus(hasChecked: true, granted: false), .missing)
    }

    func testEmptyDockNeverBlocksTheDesktopOnAnyEdge() {
        for position in DockPosition.allCases {
            let bounds = CGRect(x: -500, y: 200, width: 900, height: 600)
            let layout = DockLayout(kinds: [], bounds: bounds, position: position, baseSize: 48, maximumSize: 96)
            XCTAssertTrue(layout.background.isEmpty)
            for x in stride(from: bounds.minX, through: bounds.maxX, by: 10) {
                for y in stride(from: bounds.minY, through: bounds.maxY, by: 10) {
                    XCTAssertFalse(layout.containsInteractivePoint(CGPoint(x: x, y: y)))
                }
            }
        }
    }

    func testMaterialCornersPassThroughButMaterialAndMagnifiedIconsRemainInteractive() {
        for position in DockPosition.allCases {
            let bounds = CGRect(x: -80, y: 30, width: 600, height: 600)
            let rest = DockLayout(kinds: [.application], bounds: bounds, position: position, baseSize: 48, maximumSize: 96)
            let center = CGPoint(x: rest.iconFrames[0].midX, y: rest.iconFrames[0].midY)
            let layout = DockLayout(kinds: [.application], bounds: bounds, position: position, baseSize: 48, maximumSize: 96, pointer: center)
            XCTAssertFalse(layout.containsInteractivePoint(CGPoint(x: layout.background.minX + 0.1, y: layout.background.minY + 0.1)))
            XCTAssertTrue(layout.containsInteractivePoint(CGPoint(x: layout.background.midX, y: layout.background.midY)))
            let icon = layout.iconFrames[0]
            XCTAssertTrue(layout.containsInteractivePoint(CGPoint(x: icon.midX, y: icon.midY)))
            XCTAssertEqual(layout.hitTest(CGPoint(x: icon.midX, y: icon.midY), kinds: [.application]), 0)
        }
    }

    func testSideDockAutohideMovesWholePanelOutsideOffsetDisplay() {
        let screen = CGRect(x: -1800, y: -300, width: 1800, height: 1200)
        for position in [DockPosition.left, .right] {
            let panel = DockLayout.panelFrame(screen: screen, position: position, depth: 360)
            let hidden = DockLayout.hiddenFrame(panel, position: position)
            XCTAssertFalse(hidden.intersects(screen))
            XCTAssertEqual(hidden.size, panel.size)
            let edge = CGPoint(x: position == .left ? screen.minX : screen.maxX - 1, y: screen.midY)
            XCTAssertTrue(DockLayout.touchesEdge(edge, screen: screen, position: position))
            XCTAssertFalse(DockLayout.touchesEdge(CGPoint(x: edge.x, y: screen.maxY + 20), screen: screen, position: position))
        }
    }

    func testStaleRecorderReleaseCannotResumeHotkeysDuringNewRecording() async {
        await MainActor.run {
            let first = UUID(), second = UUID()
            SettingsShortcutRecording.acquire(owner: first)
            SettingsShortcutRecording.acquire(owner: second)
            SettingsShortcutRecording.release(owner: first)
            XCTAssertTrue(SettingsShortcutRecording.isRecording)
            SettingsShortcutRecording.release(owner: second)
            XCTAssertFalse(SettingsShortcutRecording.isRecording)
        }
    }
}
