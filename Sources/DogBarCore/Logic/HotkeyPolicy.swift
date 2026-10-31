import Foundation

/// Input kinds from a CGEventTap, without retaining CGEvent objects.
public enum HotkeyEventKind { case keyDown, keyUp, flagsChanged, tapDisabled }
/// Commands dispatched from the tap to the switcher controller.
public enum SwitcherCommand: Equatable {
    case begin(reverse: Bool, sameAppOnly: Bool), next, previous, moveLeft, moveRight, moveUp, moveDown
    case commit, cancel, closeWindow, minimizeWindow, hideApp, quitApp, reenableTap
}
/// Decoded command plus whether the original event must be swallowed.
public struct HotkeyDecision: Equatable {
    public var command: SwitcherCommand?
    public var swallow: Bool
    public init(command: SwitcherCommand? = nil, swallow: Bool = false) { self.command = command; self.swallow = swallow }
}
/// Pure decoding configuration. The service retains session state and applies decisions.
public struct HotkeyConfiguration {
    public var enabled = true
    public var shortcut: KeyboardShortcut = .switcher
    public var sameAppEnabled = false
    public var sameAppShortcut: KeyboardShortcut = .sameApp
    public var closeWithW = true
    public var minimizeWithM = true
    public var hideWithH = true
    public var quitWithQ = true
    public init() {}
}
/// Decode physical keys and modifier transitions. Caps Lock and device-specific flags are ignored.
public enum HotkeyPolicy {
    public static func decode(kind: HotkeyEventKind, keyCode: UInt16 = 0, flags: HotkeyModifiers = [], isSessionActive: Bool, heldModifiers: HotkeyModifiers? = nil, configuration: HotkeyConfiguration = .init()) -> HotkeyDecision {
        if kind == .tapDisabled { return .init(command: .reenableTap) }
        guard configuration.enabled else { return .init() }
        let modifiers = flags.intersection(.relevant)
        let held = (heldModifiers ?? configuration.shortcut.modifiers).intersection(.relevant)
        if isSessionActive && kind == .flagsChanged && !modifiers.isSuperset(of: held) { return .init(command: .commit) }
        guard kind == .keyDown || kind == .keyUp else { return .init() }
        func matches(_ shortcut: KeyboardShortcut) -> Bool {
            let required = shortcut.modifiers.intersection(.relevant)
            return keyCode == shortcut.keyCode && (modifiers == required || modifiers == required.union(.shift))
        }
        let sameApp = configuration.sameAppEnabled && matches(configuration.sameAppShortcut)
        let trigger = matches(configuration.shortcut) || sameApp
        if trigger {
            if kind == .keyUp { return .init(swallow: true) }
            if isSessionActive { return .init(command: modifiers.contains(.shift) ? .previous : .next, swallow: true) }
            return .init(command: .begin(reverse: modifiers.contains(.shift), sameAppOnly: sameApp), swallow: true)
        }
        guard isSessionActive else { return .init() }
        let command: SwitcherCommand?
        switch keyCode {
        case 53: command = .cancel
        case 123: command = .moveLeft
        case 124: command = .moveRight
        case 125: command = .moveDown
        case 126: command = .moveUp
        case 13: command = configuration.closeWithW ? .closeWindow : nil
        case 46: command = configuration.minimizeWithM ? .minimizeWindow : nil
        case 4: command = configuration.hideWithH ? .hideApp : nil
        case 12: command = configuration.quitWithQ ? .quitApp : nil
        default: command = nil
        }
        return .init(command: kind == .keyDown ? command : nil, swallow: command != nil)
    }
}
