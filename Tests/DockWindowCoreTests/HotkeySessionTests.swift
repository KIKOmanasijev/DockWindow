import XCTest
@testable import DockWindowCore

final class HotkeySessionTests: XCTestCase {
    func testReleaseCommitsOnceAndOwnsTriggerUpWithoutModifiers() {
        var session = HotkeySessionState()
        let configuration = HotkeyConfiguration()
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 48, flags: .option,
            configuration: configuration, canDeliver: true),
            HotkeyDecision(command: .begin(reverse: false, sameAppOnly: false), swallow: true))
        XCTAssertEqual(session.process(kind: .flagsChanged, configuration: configuration,
            canDeliver: true), HotkeyDecision(command: .commit))
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.suppressedKeys, [48])
        XCTAssertNil(session.process(kind: .flagsChanged, configuration: configuration, canDeliver: true).command)
        XCTAssertTrue(session.process(kind: .keyUp, keyCode: 48, configuration: configuration, canDeliver: true).swallow)
        XCTAssertFalse(session.process(kind: .keyUp, keyCode: 48, configuration: configuration, canDeliver: true).swallow)
    }

    func testForeignKeyUpIsNeverSwallowed() {
        var session = HotkeySessionState()
        let configuration = HotkeyConfiguration()
        XCTAssertFalse(session.process(kind: .keyUp, keyCode: 48, flags: .option,
            configuration: configuration, canDeliver: true).swallow)
        _ = session.process(kind: .keyDown, keyCode: 48, flags: .option, configuration: configuration, canDeliver: true)
        XCTAssertFalse(session.process(kind: .keyUp, keyCode: 13, flags: .option,
            configuration: configuration, canDeliver: true).swallow)
    }

    func testSameAppSessionRetainsItsOwnMultiModifierTriggerAcrossEdits() {
        var session = HotkeySessionState()
        var configuration = HotkeyConfiguration()
        configuration.sameAppEnabled = true
        configuration.sameAppShortcut = KeyboardShortcut(keyCode: 50, modifiers: [.option, .control])
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 50, flags: [.option, .control, .shift],
            configuration: configuration, canDeliver: true).command, .begin(reverse: true, sameAppOnly: true))
        configuration.sameAppEnabled = false
        configuration.shortcut = KeyboardShortcut(keyCode: 49, modifiers: .command)
        XCTAssertNil(session.process(kind: .flagsChanged, flags: [.option, .control],
            configuration: configuration, canDeliver: true).command)
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 50, flags: [.option, .control],
            configuration: configuration, canDeliver: true).command, .next)
        XCTAssertEqual(session.process(kind: .flagsChanged, flags: .option,
            configuration: configuration, canDeliver: true).command, .commit)
        XCTAssertTrue(session.process(kind: .keyUp, keyCode: 50, flags: .option,
            configuration: configuration, canDeliver: true).swallow)
    }

    func testReverseRepeatAndActionKeyOwnershipAfterCancel() {
        var session = HotkeySessionState()
        let configuration = HotkeyConfiguration()
        _ = session.process(kind: .keyDown, keyCode: 48, flags: .option, configuration: configuration, canDeliver: true)
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 48, flags: [.option, .shift], isRepeat: true,
            configuration: configuration, canDeliver: true).command, .previous)
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 13, flags: .option,
            configuration: configuration, canDeliver: true).command, .closeWindow)
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 53, flags: .option,
            configuration: configuration, canDeliver: true).command, .cancel)
        XCTAssertFalse(session.isActive)
        for key in [UInt16(13), 53, 48] {
            XCTAssertTrue(session.process(kind: .keyUp, keyCode: key, configuration: configuration, canDeliver: true).swallow)
        }
    }

    func testDisabledAndUnavailableDeliveryNeverSwallowOrRetainState() {
        for canDeliver in [true, false] {
            var session = HotkeySessionState()
            var configuration = HotkeyConfiguration()
            _ = session.process(kind: .keyDown, keyCode: 48, flags: .option, configuration: configuration, canDeliver: true)
            if canDeliver { configuration.enabled = false }
            XCTAssertEqual(session.process(kind: .keyDown, keyCode: 48, flags: .option,
                configuration: configuration, canDeliver: canDeliver), HotkeyDecision())
            XCTAssertFalse(session.isActive)
            XCTAssertTrue(session.suppressedKeys.isEmpty)
            XCTAssertFalse(session.process(kind: .keyUp, keyCode: 48, flags: .option,
                configuration: configuration, canDeliver: canDeliver).swallow)
        }
    }

    func testReleaseBeforeTabUpCannotReopenFromAutorepeat() {
        var session = HotkeySessionState()
        let configuration = HotkeyConfiguration()
        _ = session.process(kind: .keyDown, keyCode: 48, flags: .option, configuration: configuration, canDeliver: true)
        _ = session.process(kind: .flagsChanged, configuration: configuration, canDeliver: true)
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 48, flags: .option, isRepeat: true,
            configuration: configuration, canDeliver: true), HotkeyDecision(swallow: true))
        XCTAssertFalse(session.isActive)
        _ = session.process(kind: .keyUp, keyCode: 48, configuration: configuration, canDeliver: true)
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 48, flags: .option,
            configuration: configuration, canDeliver: true).command, .begin(reverse: false, sameAppOnly: false))
    }

    func testLiveActionGateDoesNotLeakAlreadyOwnedKeyUp() {
        var session = HotkeySessionState()
        var configuration = HotkeyConfiguration()
        _ = session.process(kind: .keyDown, keyCode: 48, flags: .option, configuration: configuration, canDeliver: true)
        _ = session.process(kind: .keyDown, keyCode: 13, flags: .option, configuration: configuration, canDeliver: true)
        configuration.closeWithW = false
        XCTAssertTrue(session.process(kind: .keyUp, keyCode: 13, flags: .option,
            configuration: configuration, canDeliver: true).swallow)
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 13, flags: .option,
            configuration: configuration, canDeliver: true), HotkeyDecision())
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 0, flags: .option,
            configuration: configuration, canDeliver: true), HotkeyDecision())
    }

    func testTabUpBeforeModifierReleaseKeepsSessionAndShiftReleaseDoesNotCommit() {
        var session = HotkeySessionState()
        let configuration = HotkeyConfiguration()
        _ = session.process(kind: .keyDown, keyCode: 48, flags: [.option, .shift], configuration: configuration, canDeliver: true)
        XCTAssertTrue(session.process(kind: .keyUp, keyCode: 48, flags: .option,
            configuration: configuration, canDeliver: true).swallow)
        XCTAssertTrue(session.isActive)
        XCTAssertNil(session.process(kind: .flagsChanged, flags: .option,
            configuration: configuration, canDeliver: true).command)
        XCTAssertEqual(session.process(kind: .flagsChanged, configuration: configuration, canDeliver: true).command, .commit)
    }

    func testDisabledTapRequestsReenableEvenWhenFeatureDisabled() {
        var session = HotkeySessionState()
        var configuration = HotkeyConfiguration()
        configuration.enabled = false
        XCTAssertEqual(session.process(kind: .tapDisabled, configuration: configuration, canDeliver: false),
            HotkeyDecision(command: .reenableTap))
    }

    func testModifierFreeShortcutPassesThroughAndResetAllowsNewSession() {
        var session = HotkeySessionState()
        var configuration = HotkeyConfiguration()
        configuration.shortcut.modifiers = []
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 48, configuration: configuration,
            canDeliver: true), HotkeyDecision())
        configuration.shortcut = .switcher
        _ = session.process(kind: .keyDown, keyCode: 48, flags: .option, configuration: configuration, canDeliver: true)
        session.reset()
        XCTAssertNil(session.heldShortcut)
        XCTAssertTrue(session.suppressedKeys.isEmpty)
        XCTAssertEqual(session.process(kind: .keyDown, keyCode: 48, flags: .option,
            configuration: configuration, canDeliver: true).command, .begin(reverse: false, sameAppOnly: false))
    }
}
