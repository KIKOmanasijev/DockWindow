import Foundation

/// Stable MRU ordering and focus updates. Equal timestamps preserve input order.
public enum MRUPolicy {
    public static func ordered(_ windows: [TrackedWindow]) -> [TrackedWindow] {
        windows.enumerated().sorted { a, b in
            a.element.lastFocusedAt == b.element.lastFocusedAt ? a.offset < b.offset : a.element.lastFocusedAt > b.element.lastFocusedAt
        }.map(\.element)
    }
    public static func focusing(_ id: UInt32, in windows: [TrackedWindow], at date: Date) -> [TrackedWindow] {
        ordered(windows.map { window in var copy = window; if copy.id == id { copy.lastFocusedAt = date }; return copy })
    }
}

/// Select current Spaces using the Dock display or the switcher's display setting.
public enum SpacePolicy {
    public static func currentSpaceIDs(snapshot: WindowSnapshot, displayID: String?, separateSpaces: Bool, allDisplays: Bool = false) -> Set<UInt64> {
        if !separateSpaces { return snapshot.activeSpaceID == 0 ? [] : [snapshot.activeSpaceID] }
        if allDisplays { return Set(snapshot.activeSpaceIDs.values.filter { $0 != 0 }) }
        let id = displayID.flatMap { snapshot.activeSpaceIDs[$0] } ?? snapshot.activeSpaceID
        return id == 0 ? [] : [id]
    }
    public static func membership(of window: TrackedWindow) -> [UInt64] {
        window.spaceIDs.isEmpty && window.isMinimized ? window.rememberedSpaceIDs : window.spaceIDs
    }
    public static func isOnCurrentSpace(_ window: TrackedWindow, currentSpaceIDs: Set<UInt64>) -> Bool {
        let ids = membership(of: window)
        // Unknown minimized membership belongs to every desktop. Missing Space APIs degrade to all.
        return currentSpaceIDs.isEmpty || (ids.isEmpty && window.isMinimized) || !currentSpaceIDs.isDisjoint(with: ids)
    }
    /// Preserve the last known nonempty membership, including through repeated minimized polls.
    public static func updatingMembership(of window: TrackedWindow, spaceIDs: [UInt64], isMinimized: Bool) -> TrackedWindow {
        var copy = window
        if !window.spaceIDs.isEmpty { copy.rememberedSpaceIDs = window.spaceIDs }
        if !spaceIDs.isEmpty { copy.rememberedSpaceIDs = spaceIDs }
        copy.spaceIDs = spaceIDs; copy.isMinimized = isMinimized
        return copy
    }
}

/// Options shared by switcher, preview and indicator filtering.
public struct WindowFilter {
    public var scope: WindowScope
    public var currentSpaceIDs: Set<UInt64>
    public var includeMinimized: Bool
    public var includeHiddenApps: Bool
    public var pid: pid_t?
    public var displayFrame: CGRect?
    public init(scope: WindowScope = .currentDesktop, currentSpaceIDs: Set<UInt64> = [], includeMinimized: Bool = true, includeHiddenApps: Bool = true, pid: pid_t? = nil, displayFrame: CGRect? = nil) {
        self.scope = scope; self.currentSpaceIDs = currentSpaceIDs; self.includeMinimized = includeMinimized; self.includeHiddenApps = includeHiddenApps; self.pid = pid; self.displayFrame = displayFrame
    }
    public func apply(to windows: [TrackedWindow]) -> [TrackedWindow] {
        MRUPolicy.ordered(windows.filter { w in
            (includeMinimized || !w.isMinimized) && (includeHiddenApps || !w.isAppHidden) && (pid == nil || w.pid == pid) && (scope == .allDesktops || SpacePolicy.isOnCurrentSpace(w, currentSpaceIDs: currentSpaceIDs)) && (displayFrame == nil || w.frame.intersects(displayFrame ?? .zero))
        })
    }
}

/// Server metadata for deterministic eligibility decisions before creating a tracked value.
public struct WindowCandidate {
    public var id: UInt32
    public var role: String
    public var subrole: String
    public var frame: CGRect
    public var layer: Int
    public var alpha: Double
    public init(id: UInt32, role: String = "AXWindow", subrole: String = "AXStandardWindow", frame: CGRect, layer: Int = 0, alpha: Double = 1) {
        self.id = id; self.role = role; self.subrole = subrole; self.frame = frame; self.layer = layer; self.alpha = alpha
    }
    public func isEligible(allowedSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]) -> Bool {
        id != 0 && role == "AXWindow" && allowedSubroles.contains(subrole) && frame.width >= 100 && frame.height >= 50 && layer == 0 && alpha > 0
    }
}

/// A window tile or app-level tile. Window mode uses app tiles only for windowless apps.
public enum SwitcherItem: Hashable {
    case window(TrackedWindow)
    case windowlessApp(TrackedApp)
}
/// Build switcher tiles without inventing a windowless tile for an app on another Space.
public enum SwitcherPolicy {
    public static func items(snapshot: WindowSnapshot, filter: WindowFilter, showWindowlessApps: Bool, frontmostPID: pid_t? = nil) -> [SwitcherItem] {
        var entries: [(Date, Int, SwitcherItem)] = filter.apply(to: snapshot.windows).filter { frontmostPID == nil || $0.pid == frontmostPID }.enumerated().map { ($0.element.lastFocusedAt, $0.offset, .window($0.element)) }
        if showWindowlessApps {
            for app in snapshot.apps where !snapshot.windows.contains(where: { $0.pid == app.pid }) && (frontmostPID == nil || frontmostPID == app.pid) && (filter.pid == nil || filter.pid == app.pid) && (filter.includeHiddenApps || !app.isHidden) {
                entries.append((app.lastActivatedAt, entries.count, .windowlessApp(app)))
            }
        }
        return entries.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }.map { $0.2 }
    }
    /// One stable tile per running app, including apps without windows, like macOS.
    public static func applications(snapshot: WindowSnapshot, includeHidden: Bool) -> [SwitcherItem] {
        snapshot.apps.filter { includeHidden || !$0.isHidden }.sorted {
            if $0.isFrontmost != $1.isFrontmost { return $0.isFrontmost }
            if $0.lastActivatedAt != $1.lastActivatedAt { return $0.lastActivatedAt > $1.lastActivatedAt }
            return $0.pid < $1.pid
        }.map { .windowlessApp($0) }
    }
    public static func nextIndex(current: Int, count: Int, delta: Int = 1) -> Int? {
        guard count > 0 else { return nil }
        return ((current + delta) % count + count) % count
    }
}
