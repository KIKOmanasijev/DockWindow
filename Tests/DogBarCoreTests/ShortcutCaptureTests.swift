import XCTest
@testable import DogBarCore

final class ShortcutCaptureTests: XCTestCase {
    func testCommandTabIsClaimedOnceWithItsKeyUp() {
        var state = ShortcutCaptureState()
        let commandTab = KeyboardShortcut(keyCode: 48, modifiers: .command)
        XCTAssertEqual(state.process(kind: .flagsChanged, flags: .command), .init())
        XCTAssertEqual(state.process(kind: .keyDown, keyCode: 48, flags: .command),
                       .init(event: .captured(commandTab), swallow: true))
        XCTAssertEqual(state.process(kind: .keyDown, keyCode: 48, flags: .command, isRepeat: true), .init(swallow: true))
        XCTAssertEqual(state.process(kind: .keyUp, keyCode: 48, flags: .command), .init(swallow: true))
        XCTAssertEqual(state.process(kind: .keyUp, keyCode: 48, flags: .command), .init())
    }

    func testCompletedCapturePassesLaterKeysThrough() {
        var state = ShortcutCaptureState()
        _ = state.process(kind: .keyDown, keyCode: 48, flags: .command)
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.process(kind: .keyDown, keyCode: 50, flags: .command), .init())
        XCTAssertEqual(state.process(kind: .keyDown, keyCode: 53), .init())
    }

    func testEscapeCancelsAndModifierFreeKeysReachTheRecorder() {
        var state = ShortcutCaptureState()
        XCTAssertEqual(state.process(kind: .keyDown, keyCode: 0), .init())
        XCTAssertEqual(state.process(kind: .keyDown, keyCode: 0, flags: .command, isRepeat: true), .init())
        XCTAssertFalse(state.isComplete)
        XCTAssertEqual(state.process(kind: .keyDown, keyCode: 53), .init(event: .cancelled, swallow: true))
    }

    func testCapsLockAndDeviceFlagsAreNotRecorded() {
        var state = ShortcutCaptureState()
        let flags = HotkeyModifiers(rawValue: HotkeyModifiers.option.rawValue | (1 << 16) | 0x20)
        XCTAssertEqual(state.process(kind: .keyDown, keyCode: 48, flags: flags),
                       .init(event: .captured(KeyboardShortcut(keyCode: 48, modifiers: .option)), swallow: true))
    }
}
