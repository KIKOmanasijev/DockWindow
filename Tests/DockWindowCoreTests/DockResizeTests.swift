import AppKit
import XCTest
@testable import DockWindowCore

final class DockResizeTests: XCTestCase {
    func testInwardDragGrowsAndOutwardDragShrinksForEveryEdge() {
        let origin = CGPoint(x: -400, y: 300)
        for (position, inward) in [(DockPosition.bottom, CGPoint(x: -400, y: 320)),
                                   (.left, CGPoint(x: -380, y: 300)), (.right, CGPoint(x: -420, y: 300))] {
            let session = DockResizeSession(size: 48, origin: origin, position: position)
            XCTAssertEqual(session.size(at: inward), 68)
            let outward = CGPoint(x: 2 * origin.x - inward.x, y: 2 * origin.y - inward.y)
            XCTAssertEqual(session.size(at: outward), 28)
            XCTAssertEqual(session.end(at: inward, cancelled: true), 48)
            XCTAssertEqual(session.end(at: inward, cancelled: false), 68)
        }
    }
    func testClampAndReturnFromBoundaryUsesOriginalAnchor() {
        let session = DockResizeSession(size: 48, origin: .zero, position: .bottom)
        XCTAssertEqual(session.size(at: CGPoint(x: 900, y: 500)), 128)
        XCTAssertEqual(session.size(at: CGPoint(x: 900, y: -500)), 16)
        XCTAssertEqual(session.size(at: CGPoint(x: 900, y: 4)), 52)
        XCTAssertEqual(session.size(at: CGPoint(x: 0, y: CGFloat.nan)), 48)
        XCTAssertEqual(DockResizeSession(size: .infinity, origin: .zero, position: .left).initialSize, 48)
    }
    func testHandleDoesNotCompeteWithIconsAtAllSizesAndEdges() {
        for position in DockPosition.allCases {
            for size in [16.0, 48, 128] {
                for kinds: [DockItem.Kind] in [[.application, .separator, .trash], [.application, .trash]] {
                    let layout = DockLayout(kinds: kinds, bounds: CGRect(x: 0, y: 0, width: 800, height: 800),
                                            position: position, baseSize: size, maximumSize: size)
                    let handle = layout.resizeHandle(kinds: kinds)
                    XCTAssertFalse(handle.isEmpty)
                    XCTAssertTrue(layout.containsInteractivePoint(CGPoint(x: handle.midX, y: handle.midY)))
                    XCTAssertNil(layout.hitTest(CGPoint(x: handle.midX, y: handle.midY), kinds: kinds))
                    for index in kinds.indices where kinds[index] != .separator {
                        XCTAssertFalse(handle.intersects(layout.iconFrames[index]))
                    }
                }
            }
        }
    }
    @MainActor func testResizeCancellationRetainsSequenceAndNeverClicksAnApp() throws {
        let suite = "DockResizeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.iconSize = 48
        let view = DockView(settings: settings)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 210)
        // No items have no resize target. A trash item provides the inward-edge grip.
        view.items = [DockItem(id: "trash", kind: .trash)]
        view.render()
        let layout = DockLayout(kinds: [.trash], bounds: view.bounds, position: .bottom, baseSize: 48, maximumSize: 48)
        let handle = layout.resizeHandle(kinds: [.trash])
        let point = CGPoint(x: handle.midX, y: handle.midY)
        var clicks = 0
        var hoverCleared = false
        view.onClick = { _ in clicks += 1 }
        view.onHover = { item, _ in if item == nil { hoverCleared = true } }
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                                  timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        XCTAssertTrue(view.isDragging)
        XCTAssertTrue(view.ownsMouseSequence)
        XCTAssertTrue(hoverCleared)
        settings.iconSize = 88
        view.cancelOperation(nil)
        XCTAssertEqual(settings.iconSize, 48)
        XCTAssertTrue(view.ownsMouseSequence)
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                                timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        view.mouseUp(with: up)
        XCTAssertFalse(view.ownsMouseSequence)
        XCTAssertFalse(view.isDragging)
        XCTAssertEqual(clicks, 0)
    }

}
