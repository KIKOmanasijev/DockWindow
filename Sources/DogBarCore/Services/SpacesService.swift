import Foundation
import CoreGraphics
import Darwin

/// Reads display topology and batched window membership without Accessibility traffic.
public final class SpacesService {
    public struct State {
        public var activeSpaceIDs: [String: UInt64]
        public var membership: [CGWindowID: [UInt64]]
        public var fullscreenSpaceIDs: Set<UInt64>
        public var hasSeparateSpaces: Bool
        public var desktopKeys: [UInt64: String] = [:]
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
                     hasSeparateSpaces: !(UserDefaults.standard.persistentDomain(forName: "com.apple.spaces")?["spans-displays"] as? Bool ?? false), desktopKeys: DesktopIdentityPolicy.keys(displays: displays), desktopNumbers: numbers)
    }
    private static func id(_ space: [String: Any]) -> UInt64? {
        (space["ManagedSpaceID"] as? NSNumber ?? space["id64"] as? NSNumber)?.uint64Value
    }
}

/// Desktop numbers and display arrangement are not identities. UUIDs follow reordered
/// Spaces; macOS's single unnamed default desktop has a dedicated stable identity.
internal enum DesktopIdentityPolicy {
    static let bootSession: String = {
        var count = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &count, nil, 0) == 0, count > 1 else { return UUID().uuidString }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &count, nil, 0) == 0 else { return UUID().uuidString }
        return String(cString: bytes)
    }()
    static func keys(displays: [[String: Any]], session: String = bootSession) -> [UInt64: String] {
        let entries = displays.flatMap { display in
            (display["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? NSNumber)?.intValue == 0 }
                .map { (display["Display Identifier"] as? String ?? "Main", $0) }
        }
        let unnamed = entries.filter { (($0.1["uuid"] as? String) ?? "").isEmpty }
        var result: [UInt64: String] = [:]
        for (display, space) in entries {
            guard let id = (space["ManagedSpaceID"] as? NSNumber ?? space["id64"] as? NSNumber)?.uint64Value else { continue }
            if let uuid = space["uuid"] as? String, !uuid.isEmpty { result[id] = "space:" + uuid.lowercased() }
            else if unnamed.count == 1 { result[id] = "system-default" }
            else if unnamed.filter({ $0.0 == display }).count == 1 { result[id] = "default-display:" + display.lowercased() }
            else { result[id] = "unidentified:\(session):\(id)" }
        }
        return result
    }
}
