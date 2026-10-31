import XCTest
@testable import DogBarCore
final class DefaultShortcutTests: XCTestCase {
    func testOptionTabDefaultPreservesSystemCommandTab() {
        XCTAssertEqual(KeyboardShortcut.switcher, KeyboardShortcut(keyCode: 48, modifiers: .option))
        XCTAssertEqual(HotkeyPolicy.decode(kind: .keyDown, keyCode: 48, flags: .option, isSessionActive: false).command, .begin(reverse: false, sameAppOnly: false))
        XCTAssertFalse(HotkeyPolicy.decode(kind: .keyDown, keyCode: 48, flags: .command, isSessionActive: false).swallow)
    }
}
