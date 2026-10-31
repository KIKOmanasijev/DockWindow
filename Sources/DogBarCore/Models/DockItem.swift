import Foundation

/// Persistent pinned app identity, independent of a running process.
public struct PinnedApp: Codable, Hashable, Identifiable {
    public var id: String { bundleIdentifier }
    public var bundleIdentifier: String
    public var url: URL
    public init(bundleIdentifier: String, url: URL) { self.bundleIdentifier = bundleIdentifier; self.url = url }
}

/// A rendered Dock entry. Only application entries carry app and pin values.
public struct DockItem: Identifiable, Hashable {
    public enum Kind: String, Codable { case application, separator, trash }
    public var id: String
    public var kind: Kind
    public var app: TrackedApp?
    public var pinnedApp: PinnedApp?
    public var isPinned: Bool
    public var isDimmed: Bool
    public init(id: String, kind: Kind = .application, app: TrackedApp? = nil, pinnedApp: PinnedApp? = nil, isPinned: Bool = false, isDimmed: Bool = false) {
        self.id = id; self.kind = kind; self.app = app; self.pinnedApp = pinnedApp; self.isPinned = isPinned; self.isDimmed = isDimmed
    }
}
