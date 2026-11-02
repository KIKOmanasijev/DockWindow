import Foundation

/// Generates the hook configuration people copy into their own files. DogBar never writes
/// Claude Code or Codex configuration; it only reads it (on request) to say whether an entry exists.
public enum AgentHookSetup {
    /// Claude Code events DogBar listens to. Documented at code.claude.com/docs/en/hooks.
    public static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                      "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
    /// Codex events DogBar listens to. Documented in the Codex hooks reference.
    public static let codexEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                                     "Stop", "Interrupt", "SessionEnd"]
    static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"]

    /// The relay command. Guarded so a moved or deleted DogBar makes the hook a silent no-op.
    public static func command(executable: String, client: AgentClient, reply: Bool = false) -> String {
        let quoted = shellQuoted(executable)
        let suffix = reply ? " \(AgentReplyChannel.argument)" : ""
        return "test -x \(quoted) && exec \(quoted) \(AgentHookRelay.argument) \(client.rawValue)\(suffix) || true"
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A `hooks` object for ~/.claude/settings.json. Every hook but SessionEnd runs with
    /// `async: true`, so Claude Code never waits on DogBar; SessionEnd runs briefly in the foreground
    /// because Claude Code may exit before a background hook finishes.
    /// With `replies`, Stop runs with `asyncRewake: true` instead: still in the background, but able to
    /// wake the finished session with a reply typed in the island (see AgentReplyChannel).
    public static func claudeSettingsJSON(executable: String, replies: Bool = true) -> String {
        let command = command(executable: executable, client: .claude)
        var hooks: [String: Any] = [:]
        for event in claudeEvents {
            var handler: [String: Any] = ["type": "command", "command": command]
            if event == "SessionEnd" { handler["timeout"] = 2 }
            else if event == "Stop" && replies {
                handler["command"] = Self.command(executable: executable, client: .claude, reply: true)
                handler["asyncRewake"] = true
                handler["timeout"] = AgentReplyChannel.hookTimeout
            } else { handler["async"] = true }
            var group: [String: Any] = ["hooks": [handler]]
            if toolEvents.contains(event) { group["matcher"] = "*" }
            hooks[event] = [group]
        }
        return json(["hooks": hooks])
    }

    /// A ~/.codex/hooks.json document. Codex hooks run in the foreground; the relay exits in milliseconds.
    public static func codexHooksJSON(executable: String) -> String {
        let command = command(executable: executable, client: .codex)
        var hooks: [String: Any] = [:]
        for event in codexEvents {
            let timeout = event == "SessionEnd" || event == "Interrupt" ? 2 : 5
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
            if event == "PreToolUse" || event == "PostToolUse" || event == "PermissionRequest" { group["matcher"] = "*" }
            hooks[event] = [group]
        }
        return json(["hooks": hooks])
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    // MARK: Read-only detection

    public enum Presence: Equatable, Sendable {
        case found(path: String), notFound, unreadable
    }

    public static func claudeConfigURLs(home: URL) -> [URL] { [home.appendingPathComponent(".claude/settings.json")] }
    public static func codexConfigURLs(home: URL) -> [URL] {
        [home.appendingPathComponent(".codex/hooks.json"), home.appendingPathComponent(".codex/config.toml")]
    }

    /// Looks for the relay argument in the given files. Reads at most 1 MB of each and changes nothing.
    public static func presence(of client: AgentClient, in urls: [URL]) -> Presence {
        let needle = "\(AgentHookRelay.argument) \(client.rawValue)"
        var sawUnreadable = false
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let data = try? handle.read(upToCount: 1 << 20) else { sawUnreadable = true; continue }
            try? handle.close()
            if String(decoding: data, as: UTF8.self).contains(needle) { return .found(path: url.path) }
        }
        return sawUnreadable ? .unreadable : .notFound
    }
}

/// One-click install and removal of DogBar's hooks, only when the person presses the button.
/// It merges into the existing JSON without touching other hooks or settings, keeps a backup of the
/// previous file next to it, writes atomically, follows symlinks, and refuses files it cannot parse.
public enum AgentHookInstaller {
    public enum Failure: Error, Equatable, LocalizedError {
        case unreadable(String), notJSONObject(String), unwritable(String)
        public var errorDescription: String? {
            switch self {
            case .unreadable(let path): return "DogBar couldn’t read \(path). Nothing was changed."
            case .notJSONObject(let path): return "\(path) isn’t a JSON object DogBar can merge into. Nothing was changed; use Show Configuration to add the hooks by hand."
            case .unwritable(let detail): return "DogBar couldn’t save the file. \(detail)"
            }
        }
    }

    public enum State: Equatable, Sendable {
        /// DogBar's hooks are present and point at this copy of DogBar.
        case installed
        /// DogBar's hooks are present but point somewhere else (an older or moved copy).
        case outdated
        case notInstalled
        case unreadable
    }

    /// The file DogBar installs into for each client.
    public static func configURL(for client: AgentClient, home: URL) -> URL {
        client == .claude ? home.appendingPathComponent(".claude/settings.json") : home.appendingPathComponent(".codex/hooks.json")
    }

    public static func document(for client: AgentClient, executable: String, replies: Bool = true) -> [String: Any] {
        let text = client == .claude ? AgentHookSetup.claudeSettingsJSON(executable: executable, replies: replies) : AgentHookSetup.codexHooksJSON(executable: executable)
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
    }

    static func marker(_ client: AgentClient) -> String { "\(AgentHookRelay.argument) \(client.rawValue)" }

    public static func state(of client: AgentClient, executable: String, home: URL, replies: Bool = true) -> State {
        let url = configURL(for: client, home: home).resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return .notInstalled }
        guard let object = try? readObject(url) else { return .unreadable }
        let found = dogBarHandlers(in: object, client: client)
        if found.isEmpty { return .notInstalled }
        // Installed means exactly the handlers this copy of DogBar would write, per event.
        let expected = dogBarHandlers(in: document(for: client, executable: executable, replies: replies), client: client)
        return found == expected ? .installed : .outdated
    }

    /// Adds (or refreshes) DogBar's hooks. Returns the backup's URL when an existing file was backed up.
    @discardableResult
    public static func install(_ client: AgentClient, executable: String, home: URL, replies: Bool = true) throws(Failure) -> URL? {
        let url = configURL(for: client, home: home).resolvingSymlinksInPath()
        var object = try existingObject(url)
        object = removing(client, from: object)
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        let ours = document(for: client, executable: executable, replies: replies)["hooks"] as? [String: Any] ?? [:]
        for (event, groups) in ours {
            hooks[event] = (hooks[event] as? [Any] ?? []) + (groups as? [Any] ?? [])
        }
        object["hooks"] = hooks
        return try write(object, to: url)
    }

    /// Removes only handlers whose command runs DogBar's relay for this client. Everything else stays.
    @discardableResult
    public static func remove(_ client: AgentClient, home: URL) throws(Failure) -> URL? {
        let url = configURL(for: client, home: home).resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let object = try existingObject(url)
        guard !dogBarCommands(in: object, client: client).isEmpty else { return nil }
        return try write(removing(client, from: object), to: url)
    }

    // MARK: Internals

    static func removing(_ client: AgentClient, from object: [String: Any]) -> [String: Any] {
        guard var hooks = object["hooks"] as? [String: Any] else { return object }
        let marker = marker(client)
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept: [Any] = groups.compactMap { item in
                guard var group = item as? [String: Any], let handlers = group["hooks"] as? [Any] else { return item }
                let remaining = handlers.filter { handler in
                    !((handler as? [String: Any])?["command"] as? String ?? "").contains(marker)
                }
                if remaining.count == handlers.count { return item }
                if remaining.isEmpty { return nil }
                group["hooks"] = remaining
                return group
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        var result = object
        if hooks.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooks }
        return result
    }

    /// Event name → DogBar handler, normalized for comparison.
    static func dogBarHandlers(in object: [String: Any], client: AgentClient) -> [String: String] {
        guard let hooks = object["hooks"] as? [String: Any] else { return [:] }
        let marker = marker(client)
        var result: [String: String] = [:]
        for (event, value) in hooks {
            let handlers = ((value as? [Any]) ?? []).flatMap { (($0 as? [String: Any])?["hooks"] as? [Any]) ?? [] }
            let ours = handlers.compactMap { $0 as? [String: Any] }.filter { ($0["command"] as? String ?? "").contains(marker) }
            guard !ours.isEmpty else { continue }
            result[event] = ours.map { handler in
                handler.keys.sorted().map { "\($0)=\(String(describing: handler[$0]!))" }.joined(separator: ";")
            }.joined(separator: "|")
        }
        return result
    }

    static func dogBarCommands(in object: [String: Any], client: AgentClient) -> [String] {
        guard let hooks = object["hooks"] as? [String: Any] else { return [] }
        let marker = marker(client)
        return hooks.values.flatMap { ($0 as? [Any]) ?? [] }
            .flatMap { (($0 as? [String: Any])?["hooks"] as? [Any]) ?? [] }
            .compactMap { ($0 as? [String: Any])?["command"] as? String }
            .filter { $0.contains(marker) }
    }

    private static func readObject(_ url: URL) throws(Failure) -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { throw .unreadable(display(url)) }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw .notJSONObject(display(url)) }
        return object
    }

    private static func existingObject(_ url: URL) throws(Failure) -> [String: Any] {
        FileManager.default.fileExists(atPath: url.path) ? try readObject(url) : [:]
    }

    private static func write(_ object: [String: Any], to url: URL) throws(Failure) -> URL? {
        let manager = FileManager.default
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var backup: URL?
            var permissions: Any?
            if manager.fileExists(atPath: url.path) {
                let copy = url.appendingPathExtension("dogbar-backup")
                try? manager.removeItem(at: copy)
                try manager.copyItem(at: url, to: copy)
                backup = copy
                permissions = try? manager.attributesOfItem(atPath: url.path)[.posixPermissions]
            }
            try (data + Data("\n".utf8)).write(to: url, options: .atomic)
            if let permissions { try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
            return backup
        } catch {
            throw .unwritable(error.localizedDescription)
        }
    }

    private static func display(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }
}
