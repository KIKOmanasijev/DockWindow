import Foundation
import Combine

/// Live settings with one UserDefaults key per value. Structured values are JSON Data.
/// Only this object's registered settings are removed by reset, preserving native Dock backups.
@MainActor
public final class AppSettings: ObservableObject {
    public nonisolated let objectWillChange = ObservableObjectPublisher()
    public let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var cachedValues: [String: Any] = [:]
    public static let keyPrefix = "DogBar."
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.registeredDefaults)
        cachedValues = currentValues()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    deinit { if let observer = observer { NotificationCenter.default.removeObserver(observer) } }
    private static func encoded<T: Encodable>(_ value: T) -> Any {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value }
        if let value = value as? Double { return value }
        if let value = value as? String { return value }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }
    private func read<T: Codable>(_ name: String, fallback: T) -> T {
        let value = defaults.object(forKey: Self.keyPrefix + name)
        if let data = value as? Data, let decoded = try? JSONDecoder().decode(T.self, from: data) { return decoded }
        return value as? T ?? fallback
    }
    private func write<T: Codable>(_ name: String, value: T) {
        objectWillChange.send()
        defaults.set(Self.encoded(value), forKey: Self.keyPrefix + name)
        cachedValues = currentValues()
    }
    private func currentValues() -> [String: Any] {
        Dictionary(uniqueKeysWithValues: Self.registeredDefaults.keys.compactMap { key in defaults.object(forKey: key).map { (key, $0) } })
    }
    /// Publish changes made by another settings instance or directly to this defaults suite.
    public func refresh() {
        let values = currentValues()
        if !NSDictionary(dictionary: values).isEqual(to: cachedValues) {
            objectWillChange.send(); cachedValues = values
        }
    }
    public func reset() {
        objectWillChange.send()
        for key in Self.registeredDefaults.keys { defaults.removeObject(forKey: key) }
        cachedValues = currentValues()
    }
    public func newWindowRule(for bundleIdentifier: String) -> NewWindowRule {
        newWindowRules.first { $0.bundleIdentifier == bundleIdentifier } ?? NewWindowRule(bundleIdentifier: bundleIdentifier)
    }
    public var launchAtLogin: Bool {
        get { read("launchAtLogin", fallback: false) }
        set { write("launchAtLogin", value: newValue) }
    }
    public var showMenuBarIcon: Bool {
        get { read("showMenuBarIcon", fallback: true) }
        set { write("showMenuBarIcon", value: newValue) }
    }
    public var isPaused: Bool {
        get { read("isPaused", fallback: false) }
        set { write("isPaused", value: newValue) }
    }
    public var useDogBarDock: Bool {
        get { read("useDogBarDock", fallback: true) }
        set { write("useDogBarDock", value: newValue) }
    }
    public var dockPosition: DockPosition {
        get { read("dockPosition", fallback: .bottom) }
        set { write("dockPosition", value: newValue) }
    }
    public var dockDisplay: DisplaySelection {
        get { read("dockDisplay", fallback: .main) }
        set { write("dockDisplay", value: newValue) }
    }
    public var iconSize: Double {
        get { read("iconSize", fallback: 48) }
        set { write("iconSize", value: newValue) }
    }
    public var magnificationEnabled: Bool {
        get { read("magnificationEnabled", fallback: false) }
        set { write("magnificationEnabled", value: newValue) }
    }
    public var magnificationSize: Double {
        get { read("magnificationSize", fallback: 96) }
        set { write("magnificationSize", value: newValue) }
    }
    public var autohide: Bool {
        get { read("autohide", fallback: false) }
        set { write("autohide", value: newValue) }
    }
    public var autohideDelay: Double {
        get { read("autohideDelay", fallback: 0.5) }
        set { write("autohideDelay", value: newValue) }
    }
    public var dockScope: WindowScope {
        get { read("dockScope", fallback: .currentDesktop) }
        set { write("dockScope", value: newValue) }
    }
    public var otherDesktopApps: OtherDesktopApps {
        get { read("otherDesktopApps", fallback: .hidden) }
        set { write("otherDesktopApps", value: newValue) }
    }
    public var indicatorStyle: IndicatorStyle {
        get { read("indicatorStyle", fallback: .perWindow) }
        set { write("indicatorStyle", value: newValue) }
    }
    public var maxDots: Int {
        get { read("maxDots", fallback: 5) }
        set { write("maxDots", value: newValue) }
    }
    public var includeMinimizedInCount: Bool {
        get { read("includeMinimizedInCount", fallback: true) }
        set { write("includeMinimizedInCount", value: newValue) }
    }
    public var useCustomDotColor: Bool {
        get { read("useCustomDotColor", fallback: false) }
        set { write("useCustomDotColor", value: newValue) }
    }
    public var dotColor: SettingsColor {
        get { read("dotColor", fallback: SettingsColor(red: 0.5, green: 0.5, blue: 0.5)) }
        set { write("dotColor", value: newValue) }
    }
    public var showRunningState: Bool {
        get { read("showRunningState", fallback: false) }
        set { write("showRunningState", value: newValue) }
    }
    public var bounceOnLaunch: Bool {
        get { read("bounceOnLaunch", fallback: true) }
        set { write("bounceOnLaunch", value: newValue) }
    }
    public var showAppNameLabels: Bool {
        get { read("showAppNameLabels", fallback: true) }
        set { write("showAppNameLabels", value: newValue) }
    }
    public var activeAppClickBehavior: ActiveAppClickBehavior {
        get { read("activeAppClickBehavior", fallback: .cycle) }
        set { write("activeAppClickBehavior", value: newValue) }
    }
    public var showTrash: Bool {
        get { read("showTrash", fallback: true) }
        set { write("showTrash", value: newValue) }
    }
    public var includeMinimizedInDock: Bool {
        get { read("includeMinimizedInDock", fallback: true) }
        set { write("includeMinimizedInDock", value: newValue) }
    }
    public var showWindowlessAppsOnLastActiveDesktop: Bool {
        get { read("showWindowlessAppsOnLastActiveDesktop", fallback: true) }
        set { write("showWindowlessAppsOnLastActiveDesktop", value: newValue) }
    }
    public var scrollToCycleWindows: Bool {
        get { read("scrollToCycleWindows", fallback: false) }
        set { write("scrollToCycleWindows", value: newValue) }
    }
    public var newWindowRules: [NewWindowRule] {
        get { read("newWindowRules", fallback: NewWindowRule.defaults) }
        set { write("newWindowRules", value: newValue) }
    }
    public var pinnedApps: [PinnedApp] {
        get { read("pinnedApps", fallback: []) }
        set { write("pinnedApps", value: newValue) }
    }
    public var hasImportedPinnedApps: Bool {
        get { read("hasImportedPinnedApps", fallback: false) }
        set { write("hasImportedPinnedApps", value: newValue) }
    }
    public var switcherEnabled: Bool {
        get { read("switcherEnabled", fallback: true) }
        set { write("switcherEnabled", value: newValue) }
    }
    public var switcherShortcut: KeyboardShortcut {
        get { read("switcherShortcut", fallback: .switcher) }
        set { write("switcherShortcut", value: newValue) }
    }
    public var sameAppShortcutEnabled: Bool {
        get { read("sameAppShortcutEnabled", fallback: false) }
        set { write("sameAppShortcutEnabled", value: newValue) }
    }
    public var sameAppShortcut: KeyboardShortcut {
        get { read("sameAppShortcut", fallback: .sameApp) }
        set { write("sameAppShortcut", value: newValue) }
    }
    public var switcherScope: WindowScope {
        get { read("switcherScope", fallback: .currentDesktop) }
        set { write("switcherScope", value: newValue) }
    }
    public var switcherScreens: DisplaySelection {
        get { read("switcherScreens", fallback: .all) }
        set { write("switcherScreens", value: newValue) }
    }
    public var switcherIncludeMinimized: Bool {
        get { read("switcherIncludeMinimized", fallback: true) }
        set { write("switcherIncludeMinimized", value: newValue) }
    }
    public var switcherIncludeHiddenApps: Bool {
        get { read("switcherIncludeHiddenApps", fallback: true) }
        set { write("switcherIncludeHiddenApps", value: newValue) }
    }
    public var switcherShowWindowlessApps: Bool {
        get { read("switcherShowWindowlessApps", fallback: true) }
        set { write("switcherShowWindowlessApps", value: newValue) }
    }
    public var switcherAppearanceDelay: Double {
        get { read("switcherAppearanceDelay", fallback: 0.12) }
        set { write("switcherAppearanceDelay", value: newValue) }
    }
    public var switcherThumbnailWidth: Double {
        get { read("switcherThumbnailWidth", fallback: 320) }
        set { write("switcherThumbnailWidth", value: newValue) }
    }
    public var switcherThumbnailHeight: Double {
        get { read("switcherThumbnailHeight", fallback: 200) }
        set { write("switcherThumbnailHeight", value: newValue) }
    }
    public var switcherMaxTilesPerRow: Int {
        get { read("switcherMaxTilesPerRow", fallback: 4) }
        set { write("switcherMaxTilesPerRow", value: newValue) }
    }
    public var switcherCloseWithW: Bool {
        get { read("switcherCloseWithW", fallback: true) }
        set { write("switcherCloseWithW", value: newValue) }
    }
    public var switcherMinimizeWithM: Bool {
        get { read("switcherMinimizeWithM", fallback: true) }
        set { write("switcherMinimizeWithM", value: newValue) }
    }
    public var switcherHideWithH: Bool {
        get { read("switcherHideWithH", fallback: true) }
        set { write("switcherHideWithH", value: newValue) }
    }
    public var switcherQuitWithQ: Bool {
        get { read("switcherQuitWithQ", fallback: true) }
        set { write("switcherQuitWithQ", value: newValue) }
    }
    public var previewsEnabled: Bool {
        get { read("previewsEnabled", fallback: true) }
        set { write("previewsEnabled", value: newValue) }
    }
    public var previewHoverDelay: Double {
        get { read("previewHoverDelay", fallback: 0.25) }
        set { write("previewHoverDelay", value: newValue) }
    }
    public var previewThumbnailHeight: Double {
        get { read("previewThumbnailHeight", fallback: 160) }
        set { write("previewThumbnailHeight", value: newValue) }
    }
    public var previewScope: WindowScope {
        get { read("previewScope", fallback: .currentDesktop) }
        set { write("previewScope", value: newValue) }
    }
    public var previewShowWindowTitles: Bool {
        get { read("previewShowWindowTitles", fallback: true) }
        set { write("previewShowWindowTitles", value: newValue) }
    }
    public var previewShowEmptyApps: Bool {
        get { read("previewShowEmptyApps", fallback: false) }
        set { write("previewShowEmptyApps", value: newValue) }
    }
    public var previewShowTrafficLights: Bool {
        get { read("previewShowTrafficLights", fallback: true) }
        set { write("previewShowTrafficLights", value: newValue) }
    }
    public var previewIncludeMinimized: Bool {
        get { read("previewIncludeMinimized", fallback: true) }
        set { write("previewIncludeMinimized", value: newValue) }
    }
    public var thumbnailRefreshInterval: Double {
        get { read("thumbnailRefreshInterval", fallback: 1) }
        set { write("thumbnailRefreshInterval", value: newValue) }
    }
    public var previewShowPointer: Bool {
        get { read("previewShowPointer", fallback: false) }
        set { write("previewShowPointer", value: newValue) }
    }
    public var theme: AppTheme {
        get { read("theme", fallback: .system) }
        set { write("theme", value: newValue) }
    }
    public var useCustomSelectionColor: Bool {
        get { read("useCustomSelectionColor", fallback: false) }
        set { write("useCustomSelectionColor", value: newValue) }
    }
    public var selectionColor: SettingsColor {
        get { read("selectionColor", fallback: SettingsColor(red: 0, green: 0.48, blue: 1)) }
        set { write("selectionColor", value: newValue) }
    }
    public var panelCornerRadius: Double {
        get { read("panelCornerRadius", fallback: 26) }
        set { write("panelCornerRadius", value: newValue) }
    }
    public var panelMaterial: PanelMaterial {
        get { read("panelMaterial", fallback: .hudWindow) }
        set { write("panelMaterial", value: newValue) }
    }
    public var reduceAnimations: Bool {
        get { read("reduceAnimations", fallback: false) }
        set { write("reduceAnimations", value: newValue) }
    }
    public var debugLogging: Bool {
        get { read("debugLogging", fallback: false) }
        set { write("debugLogging", value: newValue) }
    }
    public var allowedWindowSubroles: [String] {
        get { read("allowedWindowSubroles", fallback: ["AXStandardWindow", "AXDialog"]) }
        set { write("allowedWindowSubroles", value: newValue) }
    }
    public static var registeredDefaults: [String: Any] {
        [
            keyPrefix + "launchAtLogin": encoded(false as Bool),
            keyPrefix + "showMenuBarIcon": encoded(true as Bool),
            keyPrefix + "isPaused": encoded(false as Bool),
            keyPrefix + "useDogBarDock": encoded(true as Bool),
            keyPrefix + "dockPosition": encoded(DockPosition.bottom),
            keyPrefix + "dockDisplay": encoded(DisplaySelection.main),
            keyPrefix + "iconSize": encoded(48 as Double),
            keyPrefix + "magnificationEnabled": encoded(false as Bool),
            keyPrefix + "magnificationSize": encoded(96 as Double),
            keyPrefix + "autohide": encoded(false as Bool),
            keyPrefix + "autohideDelay": encoded(0.5 as Double),
            keyPrefix + "dockScope": encoded(WindowScope.currentDesktop),
            keyPrefix + "otherDesktopApps": encoded(OtherDesktopApps.hidden),
            keyPrefix + "indicatorStyle": encoded(IndicatorStyle.perWindow),
            keyPrefix + "maxDots": encoded(5 as Int),
            keyPrefix + "includeMinimizedInCount": encoded(true as Bool),
            keyPrefix + "useCustomDotColor": encoded(false as Bool),
            keyPrefix + "dotColor": encoded(SettingsColor(red: 0.5, green: 0.5, blue: 0.5) as SettingsColor),
            keyPrefix + "showRunningState": encoded(false),
            keyPrefix + "bounceOnLaunch": encoded(true as Bool),
            keyPrefix + "showAppNameLabels": encoded(true as Bool),
            keyPrefix + "activeAppClickBehavior": encoded(ActiveAppClickBehavior.cycle),
            keyPrefix + "showTrash": encoded(true as Bool),
            keyPrefix + "includeMinimizedInDock": encoded(true as Bool),
            keyPrefix + "showWindowlessAppsOnLastActiveDesktop": encoded(true as Bool),
            keyPrefix + "scrollToCycleWindows": encoded(false as Bool),
            keyPrefix + "newWindowRules": encoded(NewWindowRule.defaults as [NewWindowRule]),
            keyPrefix + "pinnedApps": encoded([] as [PinnedApp]),
            keyPrefix + "hasImportedPinnedApps": encoded(false as Bool),
            keyPrefix + "switcherEnabled": encoded(true as Bool),
            keyPrefix + "switcherShortcut": encoded(KeyboardShortcut.switcher),
            keyPrefix + "sameAppShortcutEnabled": encoded(false as Bool),
            keyPrefix + "sameAppShortcut": encoded(KeyboardShortcut.sameApp),
            keyPrefix + "switcherScope": encoded(WindowScope.currentDesktop),
            keyPrefix + "switcherScreens": encoded(DisplaySelection.all),
            keyPrefix + "switcherIncludeMinimized": encoded(true as Bool),
            keyPrefix + "switcherIncludeHiddenApps": encoded(true as Bool),
            keyPrefix + "switcherShowWindowlessApps": encoded(true as Bool),
            keyPrefix + "switcherAppearanceDelay": encoded(0.12 as Double),
            keyPrefix + "switcherThumbnailWidth": encoded(320 as Double),
            keyPrefix + "switcherThumbnailHeight": encoded(200 as Double),
            keyPrefix + "switcherMaxTilesPerRow": encoded(4 as Int),
            keyPrefix + "switcherCloseWithW": encoded(true as Bool),
            keyPrefix + "switcherMinimizeWithM": encoded(true as Bool),
            keyPrefix + "switcherHideWithH": encoded(true as Bool),
            keyPrefix + "switcherQuitWithQ": encoded(true as Bool),
            keyPrefix + "previewsEnabled": encoded(true as Bool),
            keyPrefix + "previewHoverDelay": encoded(0.25 as Double),
            keyPrefix + "previewThumbnailHeight": encoded(160 as Double),
            keyPrefix + "previewScope": encoded(WindowScope.currentDesktop),
            keyPrefix + "previewShowWindowTitles": encoded(true as Bool),
            keyPrefix + "previewShowEmptyApps": encoded(false as Bool),
            keyPrefix + "previewShowTrafficLights": encoded(true as Bool),
            keyPrefix + "previewIncludeMinimized": encoded(true as Bool),
            keyPrefix + "thumbnailRefreshInterval": encoded(1 as Double),
            keyPrefix + "previewShowPointer": encoded(false as Bool),
            keyPrefix + "theme": encoded(AppTheme.system),
            keyPrefix + "useCustomSelectionColor": encoded(false as Bool),
            keyPrefix + "selectionColor": encoded(SettingsColor(red: 0, green: 0.48, blue: 1) as SettingsColor),
            keyPrefix + "panelCornerRadius": encoded(26 as Double),
            keyPrefix + "panelMaterial": encoded(PanelMaterial.hudWindow),
            keyPrefix + "reduceAnimations": encoded(false as Bool),
            keyPrefix + "debugLogging": encoded(false as Bool),
            keyPrefix + "allowedWindowSubroles": encoded(["AXStandardWindow", "AXDialog"] as [String])
        ]
    }
}
