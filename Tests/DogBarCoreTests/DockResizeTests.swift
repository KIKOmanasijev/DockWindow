import AppKit
import XCTest
@testable import DogBarCore

final class DockResizeTests: XCTestCase {
    func testInwardDragGrowsAndOutwardDragShrinksForEveryEdge() {
        let origin = CGPoint(x: -400, y: 300)
        for (position, inward) in [(DockPosition.bottom, CGPoint(x: -400, y: 320)),
                                   (.left, CGPoint(x: -380, y: 300)), (.right, CGPoint(x: -420, y: 300))] {
            var session = DockResizeSession(size: 48, origin: origin, position: position)
            XCTAssertEqual(session.size(at: inward), 68)
            let outward = CGPoint(x: 2 * origin.x - inward.x, y: 2 * origin.y - inward.y)
            XCTAssertEqual(session.size(at: outward), 28)
            XCTAssertEqual(session.end(at: inward, cancelled: false), 68)
            XCTAssertEqual(session.end(at: inward, cancelled: true), 48)
        }
    }
    func testReversalAtBothLimitsDoesNotNeedToUnwindOvershoot() {
        for position in DockPosition.allCases {
            func point(_ amount: CGFloat) -> CGPoint {
                switch position {
                case .bottom: return CGPoint(x: 0, y: amount)
                case .left: return CGPoint(x: amount, y: 0)
                case .right: return CGPoint(x: -amount, y: 0)
                }
            }
            var session = DockResizeSession(size: 48, origin: .zero, position: position)
            XCTAssertEqual(session.size(at: point(500)), 128)
            XCTAssertEqual(session.size(at: point(499)), 127)
            XCTAssertEqual(session.size(at: point(-500)), 16)
            XCTAssertEqual(session.size(at: point(-499)), 17)
            XCTAssertEqual(session.size(at: point(-499)), 17, "Repeated sample must not resize again")
            XCTAssertEqual(session.end(at: point(-499), cancelled: true), 48)
        }
    }
    func testSmallMovementsAndReversalsFollowThePointerWithoutDetents() {
        var session = DockResizeSession(size: 49, origin: .zero, position: .bottom)
        for y in [0.0, 0.5, 1, 3.4, 3.6, 3.5, 2.1, 1, 2.9, 0.4, -3.6] {
            XCTAssertEqual(session.size(at: CGPoint(x: 0, y: y)), 49 + y, accuracy: 0.0001)
        }
        XCTAssertEqual(session.size(at: CGPoint(x: 0, y: CGFloat.nan)), 45.4, accuracy: 0.0001)
        XCTAssertEqual(session.size(at: CGPoint(x: 0, y: -2.6)), 46.4, accuracy: 0.0001,
                       "Invalid input does not poison the next movement")
        XCTAssertEqual(DockResizeSession(size: .infinity, origin: .zero, position: .left).initialSize, 48)
    }
    func testScreenSpaceIgnoresMovementAcrossTheDock() {
        var session = DockResizeSession(size: 48, origin: CGPoint(x: -400, y: 300), position: .bottom)
        XCTAssertEqual(session.size(at: CGPoint(x: 900, y: 300)), 48)
        XCTAssertEqual(session.size(at: CGPoint(x: 900, y: 301)), 49)
        XCTAssertEqual(session.end(at: CGPoint(x: 900, y: 301.5), cancelled: false), 49.5)
    }
    func testInwardBorderResizesWithoutCoveringIconsOrTransparentCorners() {
        for position in DockPosition.allCases {
            for size in [16.0, 48, 128] {
                let kinds: [DockItem.Kind] = [.application, .application, .separator, .trash]
                let layout = DockLayout(kinds: kinds, bounds: CGRect(x: 0, y: 0, width: 800, height: 800),
                                        position: position, baseSize: size, maximumSize: size)
                let edge = layout.resizeEdge
                XCTAssertFalse(edge.isEmpty)
                let point = CGPoint(x: edge.midX, y: edge.midY)
                XCTAssertTrue(layout.containsResizeTarget(point, kinds: kinds))
                XCTAssertTrue(layout.containsInteractivePoint(point))
                XCTAssertNil(layout.hitTest(point, kinds: kinds))
                XCTAssertFalse(layout.containsResizeTarget(CGPoint(x: layout.background.minX, y: layout.background.maxY), kinds: kinds))
                for index in kinds.indices where kinds[index] != .separator {
                    XCTAssertFalse(edge.intersects(layout.iconFrames[index]))
                }
            }
        }
    }
    @MainActor func testResizePillAppearsWithoutTextOnHoverAndDrag() throws {
        let suite = "DockResizeCueTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.showAppNameLabels = false
        let view = DockView(settings: settings)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 210)
        view.items = [DockItem(id: "trash", kind: .trash)]
        view.render()
        let edge = DockLayout(kinds: [.trash], bounds: view.bounds, position: .bottom, baseSize: 48, maximumSize: 48).resizeEdge
        let point = CGPoint(x: edge.midX, y: edge.midY)
        view.track(point)
        let label = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertTrue(label.isHidden)
        let pill = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == "resize-pill" })
        XCTAssertFalse(pill.isHidden)
        XCTAssertEqual(pill.frame.width, 28)
        XCTAssertEqual(pill.frame.height, 3)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                                  timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        var resized = false
        view.onResizeStarted = { resized = true }
        view.mouseDown(with: down)
        XCTAssertTrue(resized)
        XCTAssertFalse(pill.isHidden)
        XCTAssertTrue(label.isHidden)
        XCTAssertGreaterThan(pill.frame.width, 0)
        XCTAssertLessThanOrEqual(pill.frame.width, 36)
        XCTAssertTrue(edge.contains(CGPoint(x: pill.frame.midX, y: pill.frame.midY)))
        XCTAssertEqual(pill.frame.height, 4)
        view.stopTracking()
        XCTAssertTrue(label.isHidden)
        XCTAssertTrue(pill.isHidden)
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
    @MainActor func testLiveResizeUpdatesGeometryWithoutWritingSettingsUntilRelease() throws {
        let suite = "DockResizePersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.iconSize = 48
        let view = DockView(settings: settings)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 800, height: 210),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.items = [DockItem(id: "trash", kind: .trash)]
        view.render()
        let layout = DockLayout(kinds: [.trash], bounds: view.bounds, position: .bottom, baseSize: 48, maximumSize: 48)
        let start = CGPoint(x: layout.resizeEdge.midX, y: layout.resizeEdge.midY)
        func event(_ type: NSEvent.EventType, offset: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: start.x, y: start.y + offset),
                                            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        var liveSizes: [CGFloat] = []
        var published = 0
        let observer = settings.objectWillChange.sink { published += 1 }
        defer { observer.cancel() }
        view.onResizeChanged = { liveSizes.append($0) }
        view.mouseDown(with: try event(.leftMouseDown, offset: 0))
        view.mouseDragged(with: try event(.leftMouseDragged, offset: 20))
        XCTAssertEqual(view.displayedIconSize, 68)
        view.mouseDragged(with: try event(.leftMouseDragged, offset: 19))
        XCTAssertEqual(view.displayedIconSize, 67, "A one-point reversal is immediate")
        XCTAssertEqual(liveSizes, [68, 67])
        XCTAssertEqual(settings.iconSize, 48)
        XCTAssertEqual(defaults.double(forKey: AppSettings.keyPrefix + "iconSize"), 48)
        XCTAssertEqual(published, 0, "Dragging must not fan out settings notifications")
        view.mouseUp(with: try event(.leftMouseUp, offset: 19))
        XCTAssertEqual(settings.iconSize, 67)
        XCTAssertEqual(published, 1, "Persist once when the drag ends")
        XCTAssertFalse(view.isDragging)
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
