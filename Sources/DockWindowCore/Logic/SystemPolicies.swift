import Foundation
import CoreFoundation

/// Import native Dock plist entries without performing file or bundle access in the policy.
public enum PinnedAppsPolicy {
    public static func parse(plist: [String: Any], appExists: (URL) -> Bool, bundleIdentifierAtURL: (URL) -> String? = { _ in nil }) -> [PinnedApp] {
        guard let tiles = plist["persistent-apps"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any], let string = file["_CFURLString"] as? String else { return nil }
            let url: URL?
            if string.hasPrefix("/") { url = URL(fileURLWithPath: string) } else { url = URL(string: string) }
            guard let url = url, url.isFileURL, url.pathExtension.lowercased() == "app", appExists(url), let bundle = data["bundle-identifier"] as? String ?? bundleIdentifierAtURL(url), !bundle.isEmpty, seen.insert(bundle).inserted else { return nil }
            return PinnedApp(bundleIdentifier: bundle, url: url.standardizedFileURL)
        }
    }
}

/// A menu tree detached from AX. IDs allow the service to resolve a match to its retained element.
public struct MenuItemDescriptor: Equatable {
    public var id: String
    public var title: String
    public var isEnabled: Bool
    public var commandCharacter: String?
    public var modifiers: HotkeyModifiers
    public var children: [MenuItemDescriptor]
    public init(id: String, title: String, isEnabled: Bool = true, commandCharacter: String? = nil, modifiers: HotkeyModifiers = .command, children: [MenuItemDescriptor] = []) {
        self.id = id; self.title = title; self.isEnabled = isEnabled; self.commandCharacter = commandCharacter; self.modifiers = modifiers; self.children = children
    }
}
/// Prefer exact localized titles across the whole tree before falling back to Cmd+N.
public enum NewWindowMenuPolicy {
    public static let defaultTitles = ["New Window", "New Finder Window", "New Browser Window"]
    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "").lowercased()
    }
    public static func match(in roots: [MenuItemDescriptor], titles: [String] = defaultTitles) -> MenuItemDescriptor? {
        func leaves(_ nodes: [MenuItemDescriptor]) -> [MenuItemDescriptor] {
            nodes.flatMap { node -> [MenuItemDescriptor] in
                guard node.isEnabled else { return [] }
                return node.children.isEmpty ? [node] : leaves(node.children)
            }
        }
        let items = leaves(roots)
        let accepted = Set(titles.map(normalized))
        return items.first { accepted.contains(normalized($0.title)) } ?? items.first { $0.commandCharacter?.lowercased() == "n" && $0.modifiers.intersection(.relevant) == .command }
    }
    /// A preferred strategy runs first, followed by the remaining safe fallbacks.
    public static func strategies(for rule: NewWindowRule) -> [NewWindowStrategy] {
        let automatic: [NewWindowStrategy] = [.menu, .shortcut, .reopen]
        return rule.strategy == .automatic ? automatic : [rule.strategy] + automatic.filter { $0 != rule.strategy }
    }
}

/// Exact, Codable property-list values used by a native Dock backup, including original types.
public indirect enum PreferenceValue: Codable, Equatable {
    case bool(Bool), integer(Int64), real(Double), string(String), data(Data), date(Date)
    case array([PreferenceValue]), dictionary([String: PreferenceValue])
    public init?(propertyList value: Any) {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
            else if CFNumberIsFloatType(number) { self = .real(number.doubleValue) }
            else { self = .integer(number.int64Value) }
        } else if let value = value as? String { self = .string(value) }
        else if let value = value as? Data { self = .data(value) }
        else if let value = value as? Date { self = .date(value) }
        else if let value = value as? [Any] {
            let converted = value.compactMap { PreferenceValue(propertyList: $0) }
            guard converted.count == value.count else { return nil }; self = .array(converted)
        } else if let value = value as? [String: Any] {
            let converted = value.compactMapValues { PreferenceValue(propertyList: $0) }
            guard converted.count == value.count else { return nil }; self = .dictionary(converted)
        } else { return nil }
    }
    public var propertyListValue: Any {
        switch self {
        case .bool(let v): return v
        case .integer(let v): return v
        case .real(let v): return v
        case .string(let v): return v
        case .data(let v): return v
        case .date(let v): return v
        case .array(let v): return v.map(\.propertyListValue)
        case .dictionary(let v): return v.mapValues(\.propertyListValue)
        }
    }
}

/// Missing keys are explicit so restoring deletes values that DockWindow introduced.
public enum BackedUpPreference: Codable, Equatable { case missing, value(PreferenceValue) }
/// A single write or deletion for the service to apply to com.apple.dock.
public struct NativeDockPreferenceChange: Equatable {
    public var key: String
    public var value: PreferenceValue?
    public init(key: String, value: PreferenceValue?) { self.key = key; self.value = value }
}
/// An exact restore plan. Capturing must happen before applying the replacement Dock plan.
public enum NativeDockPolicy {
    public static let keys = ["autohide", "autohide-delay", "autohide-time-modifier", "launchanim", "workspaces-auto-swoosh"]
    public static func backup(values: [String: PreferenceValue]) -> [String: BackedUpPreference] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, values[$0].map(BackedUpPreference.value) ?? .missing) })
    }
    public static func restorePlan(backup: [String: BackedUpPreference]) -> [NativeDockPreferenceChange] {
        keys.compactMap { key in
            guard let original = backup[key] else { return nil }
            switch original { case .missing: return .init(key: key, value: nil); case .value(let value): return .init(key: key, value: value) }
        }
    }
    public static var replacementPlan: [NativeDockPreferenceChange] {
        [.init(key: "autohide", value: .bool(true)), .init(key: "autohide-delay", value: .real(1000)), .init(key: "launchanim", value: .bool(false)), .init(key: "workspaces-auto-swoosh", value: .bool(false))]
    }
    public static func shouldRestoreAfterLaunch(hasBackup: Bool, previousSessionClean: Bool, dockEnabled: Bool) -> Bool {
        hasBackup && !previousSessionClean && !dockEnabled
    }
}

/// Verify an opening attempt from tracker evidence, never from app activation alone.
public enum NewWindowVerificationPolicy {
    public static func confirmedWindow(pid: pid_t, previousWindowIDs: Set<UInt32>, requestedSpaceIDs: Set<UInt64>, windows: [TrackedWindow]) -> TrackedWindow? {
        guard !requestedSpaceIDs.isEmpty else { return nil }
        return MRUPolicy.ordered(windows).first {
            $0.pid == pid && !previousWindowIDs.contains($0.id) && !$0.spaceIDs.isEmpty && !requestedSpaceIDs.isDisjoint(with: $0.spaceIDs)
        }
    }
}
