import Foundation

/// Inputs for composition, usable on any queue without consulting settings or system services.
public struct DockCompositionOptions {
    public var scope: WindowScope
    public var currentSpaceIDs: Set<UInt64>
    public var otherDesktopApps: OtherDesktopApps
    public var includeMinimized: Bool
    public var showWindowlessAppsOnLastActiveDesktop: Bool
    public var showTrash: Bool
    public var displayFrame: CGRect?
    public init(scope: WindowScope = .currentDesktop, currentSpaceIDs: Set<UInt64> = [], otherDesktopApps: OtherDesktopApps = .hidden, includeMinimized: Bool = true, showWindowlessAppsOnLastActiveDesktop: Bool = true, showTrash: Bool = true, displayFrame: CGRect? = nil) {
        self.scope = scope; self.currentSpaceIDs = currentSpaceIDs; self.otherDesktopApps = otherDesktopApps; self.includeMinimized = includeMinimized; self.showWindowlessAppsOnLastActiveDesktop = showWindowlessAppsOnLastActiveDesktop; self.showTrash = showTrash; self.displayFrame = displayFrame
    }
}
/// Finder, ordered pins, scoped running apps, dimmed apps, then separator and Trash.
public enum DockCompositionPolicy {
    public static let finderBundleIdentifier = "com.apple.finder"
    public static func items(snapshot: WindowSnapshot, pinned: [PinnedApp], options: DockCompositionOptions = .init()) -> [DockItem] {
        let finderPin = pinned.first { $0.bundleIdentifier == finderBundleIdentifier } ?? PinnedApp(bundleIdentifier: finderBundleIdentifier, url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        var result = [DockItem(id: finderBundleIdentifier, app: snapshot.apps.first { $0.bundleIdentifier == finderBundleIdentifier }, pinnedApp: finderPin, isPinned: true)]
        var seen: Set<String> = [finderBundleIdentifier]
        for pin in pinned where seen.insert(pin.bundleIdentifier).inserted {
            result.append(DockItem(id: pin.bundleIdentifier, app: snapshot.apps.first { $0.bundleIdentifier == pin.bundleIdentifier }, pinnedApp: pin, isPinned: true))
        }
        var dimmed: [DockItem] = []
        for app in snapshot.apps {
            let key = app.bundleIdentifier ?? "pid:\(app.pid)"
            guard seen.insert(key).inserted else { continue }
            let all = snapshot.windows.filter { $0.pid == app.pid }
            let visible = WindowFilter(scope: options.scope, currentSpaceIDs: options.currentSpaceIDs, includeMinimized: options.includeMinimized, displayFrame: options.displayFrame).apply(to: all)
            if let frame = options.displayFrame, !all.isEmpty, !all.contains(where: { $0.frame.intersects(frame) }) { continue }
            let windowlessHere = all.isEmpty && options.showWindowlessAppsOnLastActiveDesktop && (app.lastActiveSpaceIDs.isEmpty || options.currentSpaceIDs.isEmpty || !options.currentSpaceIDs.isDisjoint(with: app.lastActiveSpaceIDs))
            if (options.scope == .allDesktops && options.displayFrame == nil) || !visible.isEmpty || windowlessHere {
                result.append(DockItem(id: key, app: app))
            } else if options.otherDesktopApps == .dimmed {
                dimmed.append(DockItem(id: key, app: app, isDimmed: true))
            }
        }
        result += dimmed
        if options.showTrash { result += [DockItem(id: "separator:trash", kind: .separator), DockItem(id: "trash", kind: .trash)] }
        return result
    }
}
/// Dot layout information; hollow running state is separate from filled window indicators.
public struct DotIndicators: Equatable {
    public var count: Int
    public var isHollow: Bool
    public init(count: Int, isHollow: Bool = false) { self.count = count; self.isHollow = isHollow }
}
/// Count only windows in the selected scope and cap after applying the indicator style.
public enum DotPolicy {
    public static func indicators(windows: [TrackedWindow], filter: WindowFilter, style: IndicatorStyle = .perWindow, maxDots: Int = 5, isRunning: Bool = true, showRunningState: Bool = false) -> DotIndicators {
        guard isRunning else { return .init(count: 0) }
        let count = filter.apply(to: windows).count
        if count == 0 { return .init(count: showRunningState ? 1 : 0, isHollow: showRunningState) }
        return .init(count: min(max(0, maxDots), style == .single ? 1 : count))
    }
}
/// A decision the action service can execute without accidentally activating another Space.
public enum DockClickAction: Equatable {
    case focus(UInt32), cycle, openNewWindowHere, launch, minimize, hide, none
}
/// Clicks always choose windows on the current desktop, even when the Dock lists all desktops.
public enum DockClickPolicy {
    public static func action(app: TrackedApp?, windows: [TrackedWindow], currentSpaceIDs: Set<UInt64>, activeBehavior: ActiveAppClickBehavior = .cycle) -> DockClickAction {
        guard let app = app else { return .launch }
        let local = WindowFilter(currentSpaceIDs: currentSpaceIDs, pid: app.pid).apply(to: windows)
        guard let first = local.first else { return .openNewWindowHere }
        guard app.isFrontmost else { return .focus(first.id) }
        switch activeBehavior { case .none: return .none; case .cycle: return .cycle; case .minimize: return .minimize; case .hide: return .hide }
    }
    public static func cycleTarget(windows: [TrackedWindow], pid: pid_t, currentSpaceIDs: Set<UInt64>, focusedWindowID: UInt32?) -> UInt32? {
        let local = WindowFilter(currentSpaceIDs: currentSpaceIDs, pid: pid).apply(to: windows)
        guard !local.isEmpty else { return nil }
        guard let index = local.firstIndex(where: { $0.id == focusedWindowID }) else { return local.first?.id }
        return local[(index + 1) % local.count].id
    }
}
/// Native-style cosine magnification. Distance and range use icon widths.
public enum MagnificationPolicy {
    public static func scale(distance: Double, baseSize: Double, maximumSize: Double, range: Double = 3) -> Double {
        guard distance.isFinite, baseSize.isFinite, maximumSize.isFinite, range.isFinite, baseSize > 0, range > 0, maximumSize > baseSize else { return 1 }
        let d = min(abs(distance), range)
        guard d < range else { return 1 }
        return 1 + (maximumSize / baseSize - 1) * cos(d / range * .pi / 2)
    }
}

/// Retire a launch placeholder only when ordinary Dock composition can scope its windows.
internal enum DockLaunchHandoffPolicy {
    static func isReady(pid: pid_t, snapshot: WindowSnapshot, requiresMembership: Bool) -> Bool {
        guard snapshot.apps.contains(where: { $0.pid == pid }) else { return false }
        let windows = snapshot.windows.filter { $0.pid == pid }
        guard !windows.isEmpty else { return false }
        return !requiresMembership || windows.allSatisfy {
            $0.isMinimized || !SpacePolicy.membership(of: $0).isEmpty
        }
    }
}
