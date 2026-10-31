import Foundation

/// Presentation and ownership of the global switcher.
public enum SwitcherMode: String, Codable, CaseIterable, Sendable { case windows, apps, native }

/// Scope of a window list, independent for Dock, switcher and previews.
public enum WindowScope: String, Codable, CaseIterable, Sendable { case currentDesktop, allDesktops }
/// Edge used by the replacement Dock.
public enum DockPosition: String, Codable, CaseIterable, Sendable { case bottom, left, right }
/// Display on which a panel or Dock is placed.
public enum DisplaySelection: String, Codable, CaseIterable, Sendable { case main, withMouse, all }
/// Visibility of applications on other desktops.
public enum OtherDesktopApps: String, Codable, CaseIterable, Sendable { case hidden, dimmed }
/// Style of running window indicators.
public enum IndicatorStyle: String, Codable, CaseIterable, Sendable { case perWindow, single }
/// Action for a click on an already active application.
public enum ActiveAppClickBehavior: String, Codable, CaseIterable, Sendable { case none, cycle, minimize, hide }
/// Appearance override for panels.
public enum AppTheme: String, Codable, CaseIterable, Sendable { case system, light, dark }
/// SDK-compatible material choices for translucent panels.
public enum PanelMaterial: String, Codable, CaseIterable, Sendable { case hudWindow, popover, sidebar, menu }
/// Portable sRGB color for UserDefaults storage.
public struct SettingsColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }
}
/// Modifier flags without AppKit or event-tap dependencies.
public struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let shift = Self(rawValue: 1 << 17)
    public static let control = Self(rawValue: 1 << 18)
    public static let option = Self(rawValue: 1 << 19)
    public static let command = Self(rawValue: 1 << 20)
    public static let relevant: Self = [.shift, .control, .option, .command]
}
/// A physical key and modifiers, with macOS virtual key codes.
public struct KeyboardShortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: HotkeyModifiers
    public init(keyCode: UInt16, modifiers: HotkeyModifiers = .command) { self.keyCode = keyCode; self.modifiers = modifiers }
    public static let switcher = Self(keyCode: 48, modifiers: .option)
    public static let sameApp = Self(keyCode: 50)
    public static let newWindow = Self(keyCode: 45)
}
/// Preferred opening method. Automatic uses menu, shortcut, then reopen.
public enum NewWindowStrategy: String, Codable, CaseIterable, Sendable { case automatic, menu, shortcut, reopen }
/// Per-app opening configuration, available before the Settings UI is installed.
public struct NewWindowRule: Codable, Hashable, Sendable, Identifiable {
    public var id: String { bundleIdentifier }
    public var bundleIdentifier: String
    public var strategy: NewWindowStrategy
    public var menuTitles: [String]
    public var shortcut: KeyboardShortcut
    public init(bundleIdentifier: String, strategy: NewWindowStrategy = .automatic, menuTitles: [String] = [], shortcut: KeyboardShortcut = .newWindow) {
        self.bundleIdentifier = bundleIdentifier; self.strategy = strategy; self.menuTitles = menuTitles; self.shortcut = shortcut
    }
    public static let defaults: [Self] = ["com.apple.finder", "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox", "com.apple.Terminal", "com.googlecode.iterm2"].map {
        Self(bundleIdentifier: $0, menuTitles: [$0 == "com.apple.finder" ? "New Finder Window" : "New Window"])
    }
}
