import Foundation

/// Transactional native Dock preferences. The durable backup survives process crashes and partial writes.
public actor NativeDockController {
    public enum Failure: Error { case command(String, Int32, String), invalidPreferences, invalidBackup }
    private let defaults: UserDefaults
    private let backupKey = "nativeDock.exactBackup.v1"
    private let cleanKey = "nativeDock.cleanShutdown.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var hasBackup: Bool { defaults.data(forKey: backupKey) != nil }
    /// Call before enabling UI. A stale backup is never overwritten by replacement values.
    public func beginSession(dockEnabled: Bool) throws {
        let clean = defaults.object(forKey: cleanKey) as? Bool ?? true
        if NativeDockPolicy.shouldRestoreAfterLaunch(hasBackup: hasBackup, previousSessionClean: clean, dockEnabled: dockEnabled) { try restore() }
        defaults.set(false, forKey: cleanKey); defaults.synchronize()
        if dockEnabled { try hide() }
    }
    public func hide() throws {
        if let data = defaults.data(forKey: backupKey) {
            let backup = try PropertyListDecoder().decode([String: BackedUpPreference].self, from: data)
            guard Set(backup.keys) == Set(NativeDockPolicy.keys) else { throw Failure.invalidBackup }
        }
        if !hasBackup {
            let output = try Self.run("/usr/bin/defaults", ["export", "com.apple.dock", "-"])
            guard let plist = try PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any] else { throw Failure.invalidPreferences }
            let values = plist.compactMapValues { PreferenceValue(propertyList: $0) }
            let backup = NativeDockPolicy.backup(values: values)
            defaults.set(try PropertyListEncoder().encode(backup), forKey: backupKey)
            guard defaults.synchronize() else { throw Failure.invalidBackup }
        }
        for change in NativeDockPolicy.replacementPlan { try Self.apply(change) }
        try Self.restartDock()
    }
    public func restore() throws {
        guard let data = defaults.data(forKey: backupKey) else { return }
        let backup = try PropertyListDecoder().decode([String: BackedUpPreference].self, from: data)
        guard Set(backup.keys) == Set(NativeDockPolicy.keys) else { throw Failure.invalidBackup }
        for change in NativeDockPolicy.restorePlan(backup: backup) { try Self.apply(change) }
        try Self.restartDock()
        defaults.removeObject(forKey: backupKey); defaults.synchronize()
    }
    public func endSession() throws {
        try restore()
        defaults.set(true, forKey: cleanKey); defaults.synchronize()
    }
    private static func apply(_ change: NativeDockPreferenceChange) throws {
        guard let value = change.value else {
            // defaults delete fails when the key is already absent. Check the exported domain first.
            let data = try run("/usr/bin/defaults", ["export", "com.apple.dock", "-"])
            let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
            if dictionary[change.key] != nil { _ = try run("/usr/bin/defaults", ["delete", "com.apple.dock", change.key]) }
            return
        }
        let args: [String]
        switch value {
        case .bool(let value): args = ["-bool", value ? "true" : "false"]
        case .integer(let value): args = ["-int", String(value)]
        case .real(let value): args = ["-float", String(value)]
        case .string(let value): args = ["-string", value]
        default:
            let data = try PropertyListSerialization.data(fromPropertyList: value.propertyListValue, format: .xml, options: 0)
            guard let string = String(data: data, encoding: .utf8) else { throw Failure.invalidPreferences }
            args = [string]
        }
        _ = try run("/usr/bin/defaults", ["write", "com.apple.dock", change.key] + args)
    }
    private static func restartDock() throws { _ = try run("/usr/bin/killall", ["Dock"]) }
    private static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        // Small diagnostics go to stderr, never into a pipe that could deadlock behind stdout.
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.command(executable, process.terminationStatus, arguments.first ?? "") }
        return data
    }
}
