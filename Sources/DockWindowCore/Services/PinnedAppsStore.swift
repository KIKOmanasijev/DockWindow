import AppKit
import Combine

/// Ordered app pins in DockWindow preferences. Never changes the native persistent-apps list.
@MainActor public final class PinnedAppsStore: ObservableObject {
    @Published public private(set) var apps: [PinnedApp] = []
    private let defaults: UserDefaults
    private let key = "pinnedApps.v1"
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? PropertyListDecoder().decode([PinnedApp].self, from: data) { apps = saved }
        else { reimportNativeDock() }
    }
    public func reimportNativeDock() {
        let plist = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        apps = PinnedAppsPolicy.parse(plist: plist, appExists: { FileManager.default.fileExists(atPath: $0.path) }, bundleIdentifierAtURL: { Bundle(url: $0)?.bundleIdentifier })
        save()
    }
    public func pin(bundleIdentifier: String, url: URL, at index: Int? = nil) {
        guard !apps.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        apps.insert(PinnedApp(bundleIdentifier: bundleIdentifier, url: url), at: min(max(0, index ?? apps.count), apps.count)); save()
    }
    public func unpin(bundleIdentifier: String) { apps.removeAll { $0.bundleIdentifier == bundleIdentifier }; save() }
    public func move(from source: Int, to destination: Int) {
        guard apps.indices.contains(source) else { return }
        let value = apps.remove(at: source)
        apps.insert(value, at: min(max(0, destination), apps.count)); save()
    }
    private func save() { if let data = try? PropertyListEncoder().encode(apps) { defaults.set(data, forKey: key) } }
}
