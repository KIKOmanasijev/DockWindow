import Foundation
import CoreGraphics

/// Reads display topology and batched window membership without Accessibility traffic.
public final class SpacesService {
    public struct State {
        public var activeSpaceIDs: [String: UInt64]
        public var membership: [CGWindowID: [UInt64]]
        public var fullscreenSpaceIDs: Set<UInt64>
        public var hasSeparateSpaces: Bool
        public var desktopNumbers: [UInt64: Int]
    }
    public init() {}
    public func read(windowIDs: [CGWindowID]) -> State {
        let sky = SkyLight.shared
        let displays = sky.managedDisplays()
        var active: [String: UInt64] = [:]
        var all = Set<UInt64>()
        var fullscreen = Set<UInt64>()
        var numbers: [UInt64: Int] = [:]
        for display in displays {
            let key = display["Display Identifier"] as? String ?? "Main"
            if let current = display["Current Space"] as? [String: Any], let id = Self.id(current) { active[key] = id; all.insert(id) }
            for (index, space) in (display["Spaces"] as? [[String: Any]] ?? []).enumerated() {
                guard let id = Self.id(space) else { continue }
                all.insert(id)
                numbers[id] = index + 1
                if (space["type"] as? NSNumber)?.intValue == 4 { fullscreen.insert(id) }
            }
        }
        if active.isEmpty, let fallback = sky.activeSpace() { active["Main"] = fallback; all.insert(fallback) }
        // A union request is useful for discovering memberships missing from the topology.
        if let occupied = sky.spaces(containing: windowIDs) { all.formUnion(occupied) }
        var membership: [CGWindowID: [UInt64]] = [:]
        let wanted = Set(windowIDs)
        for space in all.sorted() {
            guard let ids = sky.windows(on: space) else { continue }
            for id in ids.intersection(wanted) { membership[id, default: []].append(space) }
        }
        // Some offscreen surfaces are omitted from inverse inventories. Singleton calls recover those gaps.
        for id in wanted where membership[id] == nil {
            if let spaces = sky.spaces(containing: [id]), !spaces.isEmpty { membership[id] = spaces }
        }
        return State(activeSpaceIDs: active, membership: membership, fullscreenSpaceIDs: fullscreen,
                     hasSeparateSpaces: !(UserDefaults.standard.persistentDomain(forName: "com.apple.spaces")?["spans-displays"] as? Bool ?? false), desktopNumbers: numbers)
    }
    private static func id(_ space: [String: Any]) -> UInt64? {
        (space["ManagedSpaceID"] as? NSNumber ?? space["id64"] as? NSNumber)?.uint64Value
    }
}
