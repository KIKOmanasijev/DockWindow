import XCTest
final class ScaffoldTests: XCTestCase {
    func testBundleMetadata() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.dockwindow.app")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, false)
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
    }
}
