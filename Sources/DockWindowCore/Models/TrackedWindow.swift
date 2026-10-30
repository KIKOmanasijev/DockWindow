import AppKit

/// A window value without Accessibility references. Coordinates are global screen coordinates.
public struct TrackedWindow: Identifiable, Hashable, Sendable {
    public let id: CGWindowID
    public let pid: pid_t
    public let bundleIdentifier: String?
    public var title: String
    public var frame: CGRect
    public var spaceIDs: [UInt64]
    public var isMinimized: Bool
    public var isAppHidden: Bool
    public var isFullscreen: Bool
    public var lastFocusedAt: Date
    public var rememberedSpaceIDs: [UInt64]
    public init(id: CGWindowID, pid: pid_t = 0, bundleIdentifier: String? = nil, title: String = "", frame: CGRect = .zero, spaceIDs: [UInt64] = [], isMinimized: Bool = false, isAppHidden: Bool = false, isFullscreen: Bool = false, lastFocusedAt: Date = .distantPast, rememberedSpaceIDs: [UInt64] = []) {
        self.id = id; self.pid = pid; self.bundleIdentifier = bundleIdentifier; self.title = title; self.frame = frame; self.spaceIDs = spaceIDs; self.isMinimized = isMinimized; self.isAppHidden = isAppHidden; self.isFullscreen = isFullscreen; self.lastFocusedAt = lastFocusedAt; self.rememberedSpaceIDs = rememberedSpaceIDs
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id); hasher.combine(pid); hasher.combine(bundleIdentifier); hasher.combine(title)
        hasher.combine(frame.origin.x); hasher.combine(frame.origin.y); hasher.combine(frame.width); hasher.combine(frame.height)
        hasher.combine(spaceIDs); hasher.combine(isMinimized); hasher.combine(isAppHidden); hasher.combine(isFullscreen); hasher.combine(lastFocusedAt); hasher.combine(rememberedSpaceIDs)
    }
}
