import Foundation

/// Which coding agent sent an event. Only clients with documented lifecycle hooks are supported.
public enum AgentClient: String, Codable, CaseIterable, Sendable {
    case claude, codex
    public var displayName: String { self == .claude ? "Claude Code" : "Codex" }
}

/// One compact, validated hook observation. The hook relay builds it from the client's own hook
/// JSON and sends it to DogBar; DogBar validates it again because the socket is a trust boundary.
/// It carries only the fields the island shows: tool inputs never leave the relay, prompts only as a 300-character excerpt.
public struct AgentEvent: Codable, Equatable, Sendable {
    public static let wireVersion = 1
    /// Largest datagram DogBar reads. Everything a valid relay sends is far smaller.
    public static let maximumWireSize = 8192

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case sessionStart = "SessionStart", sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse", postToolUse = "PostToolUse", postToolUseFailure = "PostToolUseFailure"
        case permissionRequest = "PermissionRequest", notification = "Notification"
        case stop = "Stop", stopFailure = "StopFailure", interrupt = "Interrupt"
    }

    public var v: Int = AgentEvent.wireVersion
    public var client: AgentClient
    public var event: Kind
    /// The client's session_id.
    public var sid: String
    /// When the hook ran (seconds since 1970), stamped by the relay. Async hooks can arrive out of order.
    public var ts: Double
    public var cwd: String?
    public var tool: String?
    public var toolUseID: String?
    /// Set when a subagent or teammate fired the hook (Claude's agent_id). Kept, never mapped to a parent.
    public var agentID: String?
    public var agentType: String?
    public var notificationType: String?
    /// Assistant output from Stop (last_assistant_message) or a Notification message. Bounded.
    public var message: String?
    public var title: String?
    public var model: String?
    public var reason: String?
    public var error: String?
    /// The person's prompt (UserPromptSubmit), clamped. Shown so a session is recognizable.
    public var prompt: String?
    /// The prompt was a reply sent from DogBar's island (Claude Code reports it as hook feedback).
    public var promptViaDogBar: Bool?
    /// The process that ran the hook (the agent CLI). DogBar walks up from it to find the app hosting the session.
    public var hostPID: Int32?
    /// Stop only, when replies are on: the relay's private socket, waiting for a reply or a cancel.
    public var replyTo: String?

    public init(client: AgentClient, event: Kind, sid: String, ts: Double, cwd: String? = nil, tool: String? = nil,
                toolUseID: String? = nil, agentID: String? = nil, agentType: String? = nil, notificationType: String? = nil,
                message: String? = nil, title: String? = nil, model: String? = nil, reason: String? = nil, error: String? = nil) {
        self.client = client; self.event = event; self.sid = sid; self.ts = ts; self.cwd = cwd; self.tool = tool
        self.toolUseID = toolUseID; self.agentID = agentID; self.agentType = agentType; self.notificationType = notificationType
        self.message = message; self.title = title; self.model = model; self.reason = reason; self.error = error
    }

    // MARK: Limits

    enum Limit {
        static let identifier = 128
        static let cwd = 1024
        static let name = 128
        static let message = 4000
        /// The reply must fit the datagram with everything else, whatever the script.
        static let messageBytes = 5000
        static let title = 200
        static let prompt = 300
    }

    public enum ValidationError: Error, Equatable {
        case tooLarge, malformed, unsupportedVersion, invalidSession, invalidTimestamp
    }

    /// Decodes and validates untrusted bytes. Strings are clamped rather than rejected, except the
    /// session identifier, which must be a short printable token.
    public static func decode(_ data: Data) throws -> AgentEvent {
        guard data.count <= maximumWireSize else { throw ValidationError.tooLarge }
        let decoded: AgentEvent
        do { decoded = try JSONDecoder().decode(AgentEvent.self, from: data) } catch { throw ValidationError.malformed }
        guard decoded.v == wireVersion else { throw ValidationError.unsupportedVersion }
        return try decoded.validated()
    }

    public func validated() throws -> AgentEvent {
        guard Self.isValidIdentifier(sid) else { throw ValidationError.invalidSession }
        guard ts.isFinite, ts > 1_500_000_000, ts < 4_000_000_000 else { throw ValidationError.invalidTimestamp }
        var copy = self
        copy.cwd = Self.clean(cwd, limit: Limit.cwd, singleLine: true)
        copy.tool = Self.clean(tool, limit: Limit.name, singleLine: true)
        copy.toolUseID = Self.clean(toolUseID, limit: Limit.identifier, singleLine: true)
        copy.agentID = Self.clean(agentID, limit: Limit.identifier, singleLine: true)
        copy.agentType = Self.clean(agentType, limit: Limit.name, singleLine: true)
        copy.notificationType = Self.clean(notificationType, limit: Limit.name, singleLine: true)
        copy.message = Self.clean(message, limit: Limit.message, singleLine: false).map { Self.clampBytes($0, Limit.messageBytes) }
        copy.title = Self.clean(title, limit: Limit.title, singleLine: true)
        copy.model = Self.clean(model, limit: Limit.name, singleLine: true)
        copy.reason = Self.clean(reason, limit: Limit.name, singleLine: true)
        copy.error = Self.clean(error, limit: Limit.name, singleLine: true)
        copy.prompt = Self.clean(prompt, limit: Limit.prompt, singleLine: true)
        if let pid = hostPID, pid <= 1 { copy.hostPID = nil }
        if let path = replyTo, !AgentReplyChannel.isValidReplyPath(path) { copy.replyTo = nil }
        return copy
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), data.count <= Self.maximumWireSize else { return nil }
        return data
    }

    /// Cuts on a character boundary so the UTF-8 size stays within `bytes`.
    static func clampBytes(_ text: String, _ bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var result = ""
        var used = 0
        for character in text {
            let size = character.utf8.count
            if used + size > bytes - 3 { break }
            result.append(character); used += size
        }
        return result + "…"
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= Limit.identifier else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || "-_.:".unicodeScalars.contains(scalar)
        }
    }

    /// Drops control characters (keeping newlines in multi-line text), trims, and clamps by characters.
    static func clean(_ value: String?, limit: Int, singleLine: Bool) -> String? {
        guard let value else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if scalar == "\n" || scalar == "\t" {
                scalars.append(singleLine ? " " : scalar)
            } else if !CharacterSet.controlCharacters.contains(scalar), scalar.properties.generalCategory != .format || scalar == "\u{200D}" {
                scalars.append(scalar)
            }
        }
        var text = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        if !singleLine {
            // Collapse long blank runs so a message cannot be mostly empty lines.
            while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        }
        guard !text.isEmpty else { return nil }
        if text.count > limit { text = String(text.prefix(limit - 1)) + "…" }
        return text
    }
}
