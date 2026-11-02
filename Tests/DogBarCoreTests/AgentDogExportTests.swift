import AppKit
import SwiftUI
import XCTest
@testable import DogBarCore

/// Real-window Canvas export; opt in so ordinary test runs never write landing assets.
@MainActor final class AgentDogExportTests: XCTestCase {
    func testExportDogs() async throws {
        guard let path = ProcessInfo.processInfo.environment["DOGBAR_DOG_EXPORT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set DOGBAR_DOG_EXPORT_DIR to export dog assets")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let moods: [(String, AgentMood)] = [("idle", .idle), ("working", .working), ("needs", .needsYou), ("done", .finished), ("failed", .troubled)]
        for coat in 0..<4 {
            for (name, mood) in moods {
                let host = NSHostingView(rootView: AgentDogView(coat: AgentCoat.palette(coat), mood: mood, size: 64, reduceMotion: true))
                host.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.isOpaque = false
                window.backgroundColor = .clear
                window.contentView = host
                window.appearance = NSAppearance(named: .darkAqua)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                // Explicit 2x bitmap makes output independent of the display's backing scale.
                let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                rep.size = CGSize(width: 64, height: 64)
                host.cacheDisplay(in: host.bounds, to: rep)
                var visible = 0, transparent = 0
                for y in 0..<128 {
                    for x in 0..<128 {
                        let alpha = try XCTUnwrap(rep.colorAt(x: x, y: y)).alphaComponent
                        if alpha > 0.5 { visible += 1 }
                        if alpha == 0 { transparent += 1 }
                    }
                }
                XCTAssertGreaterThan(visible, 2000, "Blank dog: \(coat)-\(name)")
                XCTAssertGreaterThan(transparent, 2000, "Missing transparency: \(coat)-\(name)")
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("dog-\(coat)-\(name).png"))
                window.close()
            }
        }
    }
}
