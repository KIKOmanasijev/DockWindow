import XCTest
@testable import DogBarCore

final class DockLayoutTests: XCTestCase {
    func testRestingBottomGeometryAndTransparentOverflow() {
        let kinds: [DockItem.Kind] = [.application, .application, .separator, .trash]
        let layout = DockLayout(kinds: kinds, bounds: CGRect(x: 0, y: 0, width: 800, height: 210), position: .bottom, baseSize: 48, maximumSize: 96)
        XCTAssertEqual(layout.background.midX, 400, accuracy: 0.001)
        XCTAssertEqual(layout.background.minY, 4)
        XCTAssertEqual(layout.iconFrames[0].width, 48)
        XCTAssertEqual(layout.iconFrames[1].minX - layout.iconFrames[0].maxX, 4)
        XCTAssertEqual(layout.hitTest(CGPoint(x: layout.iconFrames[1].midX, y: 30), kinds: kinds), 1)
        XCTAssertNil(layout.hitTest(CGPoint(x: layout.iconFrames[2].midX, y: 30), kinds: kinds))
        XCTAssertNil(layout.hitTest(CGPoint(x: 400, y: 200), kinds: kinds))
        XCTAssertEqual(layout.insertionIndex(at: CGPoint(x: -100, y: 0)), 0)
        XCTAssertEqual(layout.insertionIndex(at: CGPoint(x: 900, y: 0)), kinds.count)
    }
    func testMagnifiedFramesStayOrderedAndBackgroundGrows() {
        let kinds = Array(repeating: DockItem.Kind.application, count: 9)
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 210)
        let rest = DockLayout(kinds: kinds, bounds: bounds, position: .bottom, baseSize: 48, maximumSize: 96)
        let active = DockLayout(kinds: kinds, bounds: bounds, position: .bottom, baseSize: 48, maximumSize: 96, pointer: CGPoint(x: 600, y: 30))
        XCTAssertEqual(active.iconFrames[4].width, 96, accuracy: 0.001)
        XCTAssertEqual(active.iconFrames[3].width, active.iconFrames[5].width, accuracy: 0.001)
        XCTAssertGreaterThan(active.background.width, rest.background.width)
        XCTAssertEqual(active.background.midX, bounds.midX, accuracy: 0.001)
        XCTAssertTrue(active.containsInteractivePoint(CGPoint(x: active.iconFrames[4].midX, y: active.iconFrames[4].maxY - 1)))
        XCTAssertFalse(active.containsInteractivePoint(CGPoint(x: active.iconFrames[0].midX, y: active.iconFrames[4].maxY - 1)))
        for index in 1..<kinds.count { XCTAssertGreaterThanOrEqual(active.iconFrames[index].minX, active.iconFrames[index - 1].maxX) }
    }
    func testSideDockMirrorsInwardAxisAndHitTests() {
        let kinds: [DockItem.Kind] = [.application, .trash]
        let bounds = CGRect(x: 0, y: 0, width: 210, height: 700)
        let left = DockLayout(kinds: kinds, bounds: bounds, position: .left, baseSize: 48, maximumSize: 96)
        let right = DockLayout(kinds: kinds, bounds: bounds, position: .right, baseSize: 48, maximumSize: 96)
        XCTAssertEqual(left.background.minX, 4)
        XCTAssertEqual(right.background.maxX, bounds.maxX - 4)
        XCTAssertEqual(left.background.midY, 350, accuracy: 0.001)
        XCTAssertEqual(left.iconFrames[0].minX, bounds.maxX - right.iconFrames[0].maxX, accuracy: 0.001)
        XCTAssertEqual(right.hitTest(CGPoint(x: right.iconFrames[1].midX, y: right.iconFrames[1].midY), kinds: kinds), 1)
        XCTAssertEqual(right.insertionIndex(at: CGPoint(x: 0, y: bounds.maxY)), 0)
    }
    func testCrowdedMagnificationFitsScreen() {
        let kinds = Array(repeating: DockItem.Kind.application, count: 35)
        let layout = DockLayout(kinds: kinds, bounds: CGRect(x: 0, y: 0, width: 900, height: 210), position: .bottom, baseSize: 48, maximumSize: 128, pointer: CGPoint(x: 450, y: 20))
        XCTAssertGreaterThanOrEqual(layout.background.minX, -0.000001)
        XCTAssertLessThanOrEqual(layout.background.maxX, 900.000001)
        XCTAssertTrue(layout.iconFrames.allSatisfy { $0.width > 0 && $0.minX >= 0 && $0.maxX <= 900 })
    }
    func testRemovalThresholdAndPanelPositionsOnOffsetScreen() {
        let screen = CGRect(x: -1440, y: 300, width: 1440, height: 900)
        for position in DockPosition.allCases {
            let frame = DockLayout.panelFrame(screen: screen, position: position)
            XCTAssertTrue(screen.contains(frame))
            let hidden = DockLayout.hiddenFrame(frame, position: position)
            XCTAssertFalse(screen.intersects(hidden))
        }
        XCTAssertTrue(DockLayout.touchesEdge(CGPoint(x: -1000, y: 301), screen: screen, position: .bottom))
        XCTAssertFalse(DockLayout.touchesEdge(CGPoint(x: 20, y: 301), screen: screen, position: .bottom))
        let layout = DockLayout(kinds: [.application], bounds: CGRect(x: 0, y: 0, width: 800, height: 210), position: .bottom, baseSize: 48, maximumSize: 96)
        XCTAssertFalse(layout.isDragRemoval(at: CGPoint(x: 400, y: layout.background.maxY + 60)))
        XCTAssertTrue(layout.isDragRemoval(at: CGPoint(x: 400, y: layout.background.maxY + 61)))
    }
    func testEmptyDockHasFiniteGeometryAndNoHit() {
        let layout = DockLayout(kinds: [], bounds: CGRect(x: 0, y: 0, width: 800, height: 210), position: .bottom, baseSize: .nan, maximumSize: .infinity)
        XCTAssertTrue(layout.background.width.isFinite)
        XCTAssertNil(layout.hitTest(CGPoint(x: 400, y: 20), kinds: []))
        XCTAssertEqual(layout.insertionIndex(at: .zero), 0)
    }
    /// Like the system Dock: equal material inset on both sides of the icon, with running
    /// indicators overlaid in the outer inset rather than adding thickness.
    @MainActor func testIconInsetIsSymmetricAndIndicatorsDoNotAddThickness() {
        let kinds: [DockItem.Kind] = [.application, .separator, .trash]
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 800)
        for position in DockPosition.allCases {
            for size in [16.0, 48, 58, 64, 128] {
                let layout = DockLayout(kinds: kinds, bounds: bounds, position: position, baseSize: size, maximumSize: size)
                let icon = layout.iconFrames[0], material = layout.background
                let inset = DockLayout.edgeInset(for: size)
                let (outer, inner, thickness): (CGFloat, CGFloat, CGFloat)
                switch position {
                case .bottom: (outer, inner, thickness) = (icon.minY - material.minY, material.maxY - icon.maxY, material.height)
                case .left: (outer, inner, thickness) = (icon.minX - material.minX, material.maxX - icon.maxX, material.width)
                case .right: (outer, inner, thickness) = (material.maxX - icon.maxX, icon.minX - material.minX, material.width)
                }
                XCTAssertEqual(outer, inner, accuracy: 0.001, "\(position) \(size)")
                XCTAssertEqual(outer, inset, accuracy: 0.001)
                XCTAssertEqual(layout.edgeInset, inset, accuracy: 0.001)
                XCTAssertEqual(thickness, size + 2 * inset, accuracy: 0.001)

                let layer = DockIconLayer()
                layer.frame = icon
                layer.update(image: nil, badgeText: nil, indicators: DotIndicators(count: 3), color: .white,
                             position: position, scale: 2, reduceMotion: true, baseSize: size, glass: true)
                let dots = layer.dots.path!.boundingBoxOfPath.offsetBy(dx: icon.minX, dy: icon.minY)
                XCTAssertTrue(material.contains(dots), "\(position) \(size): dots \(dots) outside \(material)")
                XCTAssertFalse(dots.intersects(icon), "\(position) \(size): dots overlap the icon")
                // The dot sits 0.62 of the inset in from the material's outer edge (≈6 pt at 58 pt).
                let fromEdge = inset - DockLayout.indicatorOffset(for: size)
                switch position {
                case .bottom: XCTAssertEqual(dots.midY, material.minY + fromEdge, accuracy: 0.001)
                case .left: XCTAssertEqual(dots.midX, material.minX + fromEdge, accuracy: 0.001)
                case .right: XCTAssertEqual(dots.midX, material.maxX - fromEdge, accuracy: 0.001)
                }
            }
        }
    }
    /// Proportions measured from the system Dock at a ~58 pt tile size.
    func testMaterialMatchesSystemDockProportions() {
        let kinds: [DockItem.Kind] = [.application, .application, .separator, .trash]
        let layout = DockLayout(kinds: kinds, bounds: CGRect(x: 0, y: 0, width: 1200, height: 210), position: .bottom, baseSize: 58, maximumSize: 58)
        let material = layout.background, frames = layout.iconFrames
        XCTAssertEqual(material.height, 77.7, accuracy: 0.5, "≈78 pt thick")
        XCTAssertEqual(layout.cornerRadius, 21.8, accuracy: 0.5, "≈22 pt corners")
        XCTAssertEqual(frames[0].minX - material.minX, layout.edgeInset, accuracy: 0.001, "End padding equals the edge inset")
        XCTAssertEqual(material.maxX - frames[3].maxX, layout.edgeInset, accuracy: 0.001)
        XCTAssertEqual(frames[3].minX - frames[1].maxX, 32.9, accuracy: 0.5, "≈33 pt between tiles across a separator")
        XCTAssertEqual(DockLayout.indicatorOffset(for: 58) + 0, 3.75, accuracy: 0.05)
        XCTAssertEqual(layout.edgeInset - DockLayout.indicatorOffset(for: 58), 6.1, accuracy: 0.1, "Dot ≈6 pt above the outer edge")
        XCTAssertEqual(DockLayout.indicatorDiameter(for: 58), 4, accuracy: 0.001)
    }
    @MainActor func testIndicatorsKeepRestingSizeAndPlaceWhileIconMagnifies() {
        let layer = DockIconLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        layer.update(image: nil, badgeText: nil, indicators: DotIndicators(count: 1), color: .white,
                     position: .bottom, scale: 2, reduceMotion: true, baseSize: 48, glass: true)
        let dot = layer.dots.path!.boundingBoxOfPath
        XCTAssertEqual(dot.width, DockLayout.indicatorDiameter(for: 48), accuracy: 0.001)
        XCTAssertEqual(dot.midY, -DockLayout.indicatorOffset(for: 48), accuracy: 0.001)
        XCTAssertEqual(layer.dots.compositingFilter as? String, "plusL")
        XCTAssertFalse(layer.dotHighlights.isHidden)
        layer.update(image: nil, badgeText: nil, indicators: DotIndicators(count: 1), color: .red,
                     position: .bottom, scale: 2, reduceMotion: true, baseSize: 48, glass: false)
        XCTAssertNil(layer.dots.compositingFilter)
        XCTAssertTrue(layer.dotHighlights.isHidden)
    }
    func testRimProfileIsBrightAtTopAndBottomAndFadesDownTheSides() {
        for length in [24.0, 78, 600] {
            let profile = DockGlassStyle.rimProfile(length: length)
            XCTAssertEqual(profile.locations.first, 0); XCTAssertEqual(profile.locations.last, 1)
            XCTAssertEqual(profile.weights.first, 1); XCTAssertEqual(profile.weights.last, 1)
            XCTAssertEqual(profile.locations, profile.locations.sorted(), "\(length)")
            XCTAssertLessThan(profile.weights.min()!, 0.5)
            for (a, b) in zip(profile.weights, profile.weights.reversed()) { XCTAssertEqual(a, b, accuracy: 0.0001) }
        }
        // Tall side Docks fade within the same ~26 pt as the corners, not a fraction of their height.
        let tall = DockGlassStyle.rimProfile(length: 600)
        XCTAssertLessThanOrEqual(tall.locations[4], 26.0 / 600 + 0.0001)
    }
    func testVibranceCoversGlassButNotIcons() {
        let kinds: [DockItem.Kind] = [.application, .separator, .trash]
        let layout = DockLayout(kinds: kinds, bounds: CGRect(x: 0, y: 0, width: 800, height: 210), position: .bottom,
                                baseSize: 48, maximumSize: 96, pointer: CGPoint(x: 400, y: 30))
        let icons = [layout.iconFrames[0], layout.iconFrames[2]]
        let path = DockGlassStyle.vibrancePath(material: layout.background, radius: layout.cornerRadius, icons: icons)
        for icon in icons { XCTAssertFalse(path.contains(CGPoint(x: icon.midX, y: min(icon.midY, layout.background.maxY - 1)), using: .evenOdd)) }
        XCTAssertTrue(path.contains(CGPoint(x: layout.iconFrames[1].midX, y: layout.background.midY), using: .evenOdd))
        XCTAssertFalse(path.contains(CGPoint(x: icons[0].midX, y: layout.background.maxY + 2), using: .evenOdd), "Magnified icons above the material are not filled")
    }
}
