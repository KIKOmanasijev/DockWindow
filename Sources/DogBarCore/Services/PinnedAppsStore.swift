import AppKit
import Combine

/// Independent ordered pins per Space. The legacy global list is retained as a backup.
@MainActor public final class PinnedAppsStore: ObservableObject {
    @Published public private(set) var apps: [PinnedApp] = []
    @Published public private(set) var activeDesktopKey: String?
    public var canEdit: Bool { activeDesktopKey != nil }
    private struct Profiles: Codable {
        var pins: [String: [PinnedApp]] = [:]
        var seed: [PinnedApp]
        var migrated = false
        var lastSelected: String?
    }
    private let defaults: UserDefaults
    private let key = "desktopPins.v2"
    private var profiles: Profiles
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? PropertyListDecoder().decode(Profiles.self, from: data) {
            profiles = saved
        } else {
            if let unreadable = defaults.data(forKey: key), defaults.data(forKey: key + ".unreadableBackup") == nil {
                defaults.set(unreadable, forKey: key + ".unreadableBackup")
            }
            let legacy = defaults.data(forKey: "pinnedApps.v1").flatMap { try? PropertyListDecoder().decode([PinnedApp].self, from: $0) }
            var seed = legacy ?? Self.nativePins()
            // Previous versions inserted Finder implicitly. Preserve it during migration
            // once, then treat it as an ordinary removable/reorderable pin.
            seed.removeAll { $0.bundleIdentifier == DockCompositionPolicy.finderBundleIdentifier }
            seed.insert(Self.finderPin, at: 0)
            profiles = Profiles(seed: seed)
        }
        apps = profiles.lastSelected.flatMap { profiles.pins[$0] } ?? profiles.seed
    }
    public func activateDesktop(_ desktopKey: String?, knownDesktopKeys: Set<String>) {
        guard let desktopKey, knownDesktopKeys.contains(desktopKey) else {
            if activeDesktopKey != nil { activeDesktopKey = nil }
            return
        }
        var changed = false
        if !profiles.migrated {
            for key in knownDesktopKeys where profiles.pins[key] == nil { profiles.pins[key] = profiles.seed }
            profiles.migrated = true; changed = true
        }
        let template = profiles.lastSelected.flatMap { profiles.pins[$0] } ?? profiles.seed
        // Initialize newly discovered background desktops too: they copy now, not
        // some later version of the Dock when the user first visits them.
        for key in knownDesktopKeys where profiles.pins[key] == nil {
            profiles.pins[key] = template; changed = true
        }
        if profiles.lastSelected != desktopKey { profiles.lastSelected = desktopKey; changed = true }
        if activeDesktopKey != desktopKey { activeDesktopKey = desktopKey }
        let pins = profiles.pins[desktopKey] ?? []
        if apps != pins { apps = pins }
        if changed { save() }
    }
    public func reimportNativeDock() {
        guard canEdit else { return }
        replace(Self.nativePins())
    }
    public func pin(bundleIdentifier: String, url: URL, at index: Int? = nil) {
        guard canEdit, !apps.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        var pins = apps
        pins.insert(PinnedApp(bundleIdentifier: bundleIdentifier, url: url), at: min(max(0, index ?? pins.count), pins.count))
        replace(pins)
    }
    public func unpin(bundleIdentifier: String) {
        guard canEdit else { return }
        replace(apps.filter { $0.bundleIdentifier != bundleIdentifier })
    }
    public func move(from source: Int, to destination: Int) {
        guard canEdit, apps.indices.contains(source) else { return }
        var pins = apps
        let value = pins.remove(at: source)
        pins.insert(value, at: min(max(0, destination), pins.count)); replace(pins)
    }
    private func replace(_ pins: [PinnedApp]) {
        guard let desktop = activeDesktopKey else { return }
        profiles.pins[desktop] = pins
        if apps != pins { apps = pins }
        save()
    }
    private static var finderPin: PinnedApp {
        PinnedApp(bundleIdentifier: DockCompositionPolicy.finderBundleIdentifier, url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
    }
    private static func nativePins() -> [PinnedApp] {
        let plist = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        return [finderPin] + PinnedAppsPolicy.parse(plist: plist, appExists: { FileManager.default.fileExists(atPath: $0.path) }, bundleIdentifierAtURL: { Bundle(url: $0)?.bundleIdentifier })
            .filter { $0.bundleIdentifier != DockCompositionPolicy.finderBundleIdentifier }
    }
    private func save() {
        if let data = try? PropertyListEncoder().encode(profiles) { defaults.set(data, forKey: key) }
    }
}
