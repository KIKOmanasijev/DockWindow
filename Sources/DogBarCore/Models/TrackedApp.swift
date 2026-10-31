import AppKit

/// A running application's presentation state. The tracker owns all system references.
public struct TrackedApp: Identifiable, Hashable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let bundleIdentifier: String?
    public let name: String
    public let bundleURL: URL?
    public var icon: NSImage
    public var isHidden: Bool
    public var isFrontmost: Bool
    public var badgeLabel: String?
    public var lastActiveSpaceIDs: [UInt64]
    public var lastActivatedAt: Date
    public init(pid: pid_t, bundleIdentifier: String? = nil, name: String = "", bundleURL: URL? = nil, icon: NSImage = NSImage(), isHidden: Bool = false, isFrontmost: Bool = false, badgeLabel: String? = nil, lastActiveSpaceIDs: [UInt64] = [], lastActivatedAt: Date = .distantPast) {
        self.pid = pid; self.bundleIdentifier = bundleIdentifier; self.name = name; self.bundleURL = bundleURL; self.icon = icon; self.isHidden = isHidden; self.isFrontmost = isFrontmost; self.badgeLabel = badgeLabel; self.lastActiveSpaceIDs = lastActiveSpaceIDs; self.lastActivatedAt = lastActivatedAt
    }
}

/// One immutable publication from the tracker, with current Spaces keyed by display UUID.
public struct WindowSnapshot {
    public var apps: [TrackedApp]
    public var windows: [TrackedWindow]
    public var activeSpaceIDs: [String: UInt64]
    public init(apps: [TrackedApp] = [], windows: [TrackedWindow] = [], activeSpaceIDs: [String: UInt64] = [:]) {
        self.apps = apps; self.windows = windows; self.activeSpaceIDs = activeSpaceIDs
    }
    /// Prefer the explicit Main entry, then the lexically first display for deterministic fallback.
    public var activeSpaceID: UInt64 { activeSpaceIDs["Main"] ?? activeSpaceIDs.sorted { $0.key < $1.key }.first?.value ?? 0 }
}
