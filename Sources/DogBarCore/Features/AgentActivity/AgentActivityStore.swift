import Foundation

/// What a session is observed doing. Only hook facts change it; inactivity alone never makes a
/// session "finished". `stale` means DogBar has not heard from a working session for a long time.
public enum AgentStatus: String, Equatable, Sendable {
    case working, needsYou, finished, idle, stale

    public var label: String {
        switch self {
        case .working: return "Working"
        case .needsYou: return "Needs you"
        case .finished: return "Turn finished"
        case .idle: return "Idle"
        case .stale: return "No recent events"
        }
    }
    /// Which session the collapsed island leads with.
    var priority: Int {
        switch self {
        case .needsYou: return 4
        case .working: return 3
        case .finished: return 2
        case .idle: return 1
        case .stale: return 0
        }
    }
}

/// One tool, grouped for the current turn. Attempts are deduplicated by tool call ID, so a start
/// and its completion count once; failures are a subset of attempts.
public struct AgentToolGroup: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public internal(set) var attempts = 0
    public internal(set) var failures = 0
    public internal(set) var running = 0
    /// Attempts fired from inside a subagent or teammate (the hook carried an agent_id).
    public internal(set) var fromSubagents = 0
    public internal(set) var lastEventAt: Date
    let order: Int
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let client: AgentClient
    public let sessionID: String
    /// ⌘1–⌘9. Assigned once, never reshuffled; nil beyond nine sessions.
    public internal(set) var slot: Int?
    /// Stable dog coat for the life of the session.
    public internal(set) var coat: Int
    public let createdAt: Date
    public internal(set) var cwd: String?
    public internal(set) var title: String?
    public internal(set) var project: String?
    public internal(set) var branch: String?
    public internal(set) var model: String?
    public internal(set) var status: AgentStatus = .idle
    public internal(set) var statusSince: Date
    /// A short, factual qualifier: the tool awaiting permission, "Interrupted", an API error type.
    public internal(set) var detail: String?
    public internal(set) var turnStartedAt: Date?
    public internal(set) var lastTurnDuration: TimeInterval?
    /// API error type from StopFailure, when the last turn ended that way.
    public internal(set) var turnError: String?
    public internal(set) var tools: [AgentToolGroup] = []
    /// Assistant output reported by the client's Stop hook, or the error text from StopFailure.
    public internal(set) var lastMessage: String?
    public internal(set) var lastMessageAt: Date?
    public internal(set) var lastMessageIsError = false
    public internal(set) var lastEventAt: Date
    public internal(set) var lastEvent: AgentEvent.Kind?
    public internal(set) var sawSubagentEvents = false
    /// The person's latest prompt, as the client reported it.
    public internal(set) var lastPrompt: String?
    /// The latest prompt was a reply sent from the island.
    public internal(set) var lastPromptViaDogBar = false
    /// The agent CLI process that last ran a hook for this session.
    public internal(set) var hostPID: Int32?
    /// A relay waiting for a reply to the last finished turn (Claude Code with replies on).
    public internal(set) var replyPath: String?
    public var canReply: Bool { replyPath != nil && status == .finished }
    /// Hook time of the newest status-changing event, so late async deliveries cannot roll status back.
    var statusStamp: Double
    var turnStamp: Double = 0
    var toolCalls: [String: Bool] = [:]
    var nextToolOrder = 0

    public var displayTitle: String { title ?? project ?? "\(client.displayName) session" }
    public var toolAttempts: Int { tools.reduce(0) { $0 + $1.attempts } }
    public var toolFailures: Int { tools.reduce(0) { $0 + $1.failures } }
    public var runningTool: String? { tools.last(where: { $0.running > 0 })?.name }
}

/// Pure session state, driven by events and an explicit clock so it is fully testable.
public struct AgentActivityStore: Equatable, Sendable {
    public static let maximumSessions = 24
    static let maximumToolCallsPerTurn = 2048
    public static let coatCount = 8
    /// Idle and finished sessions leave after this long without events.
    public static let quietRemoval: TimeInterval = 45 * 60
    /// Working or waiting sessions with no events this long are shown as stale, not as working.
    public static let staleAfter: TimeInterval = 4 * 60 * 60
    public static let staleRemoval: TimeInterval = 12 * 60 * 60

    public private(set) var sessions: [AgentSession] = []
    /// Called with a working directory; returns the repository name and branch when cheaply known.
    var resolveProject: @Sendable (String) -> (project: String?, branch: String?)

    public init(resolveProject: @escaping @Sendable (String) -> (project: String?, branch: String?) = { cwd in
        (URL(fileURLWithPath: cwd).lastPathComponent, nil)
    }) {
        self.resolveProject = resolveProject
    }

    public static func == (lhs: AgentActivityStore, rhs: AgentActivityStore) -> Bool { lhs.sessions == rhs.sessions }

    /// Sessions in stable dot order: by shortcut slot, then by arrival.
    public var ordered: [AgentSession] {
        sessions.sorted { ($0.slot ?? Int.max, $0.createdAt) < ($1.slot ?? Int.max, $1.createdAt) }
    }
    public func session(_ id: String) -> AgentSession? { sessions.first { $0.id == id } }
    /// The session the collapsed island represents: most urgent, then most recent.
    public var lead: AgentSession? {
        sessions.max { ($0.status.priority, $0.lastEventAt) < ($1.status.priority, $1.lastEventAt) }
    }

    static func key(_ client: AgentClient, _ sid: String) -> String { "\(client.rawValue):\(sid)" }

    // MARK: Events

    public mutating func apply(_ event: AgentEvent) {
        let at = Date(timeIntervalSince1970: event.ts)
        let key = Self.key(event.client, event.sid)
        if event.event == .sessionEnd {
            sessions.removeAll { $0.id == key }
            return
        }
        var index = sessions.firstIndex { $0.id == key }
        if index == nil {
            // Make room first, so the newcomer can take a freed shortcut slot and coat.
            trimToLimit(adding: 1)
            sessions.append(makeSession(key: key, event: event, at: at))
            index = sessions.count - 1
        }
        guard let index else { return }
        var session = sessions[index]
        session.lastEventAt = max(session.lastEventAt, at)
        session.lastEvent = event.event
        if let model = event.model { session.model = model }
        if let title = event.title { session.title = title }
        if event.agentID != nil { session.sawSubagentEvents = true }
        if let pid = event.hostPID, event.agentID == nil { session.hostPID = pid }
        if let cwd = event.cwd, cwd != session.cwd || event.event == .userPromptSubmit {
            session.cwd = cwd
            let resolved = resolveProject(cwd)
            session.project = resolved.project ?? session.project
            session.branch = resolved.branch
        }
        let fresh = event.ts >= session.statusStamp
        func setStatus(_ status: AgentStatus, detail: String? = nil) {
            guard fresh else { return }
            if session.status != status { session.statusSince = at }
            session.status = status
            session.detail = detail
            session.statusStamp = event.ts
            // Any newer status ends the chance to answer the previous turn from the island.
            if event.event != .stop || event.replyTo == nil { session.replyPath = nil }
        }
        switch event.event {
        case .sessionStart:
            if session.status == .stale { setStatus(.idle) }
        case .userPromptSubmit:
            guard fresh else { break }
            setStatus(.working)
            if let prompt = event.prompt {
                if event.promptViaDogBar == true {
                    session.lastPrompt = prompt; session.lastPromptViaDogBar = true
                } else if let shown = AgentPromptText.display(prompt) {
                    // Older relays forwarded raw markup; clean it here too.
                    session.lastPrompt = shown.text; session.lastPromptViaDogBar = shown.viaDogBar
                }
            }
            session.turnStartedAt = at
            session.turnStamp = event.ts
            session.turnError = nil
            session.tools = []
            session.toolCalls = [:]
        case .preToolUse, .postToolUse, .postToolUseFailure:
            recordTool(event, at: at, in: &session)
            // Tool activity after a permission prompt means the prompt was answered.
            if session.status != .working, event.agentID == nil || session.status == .needsYou || session.status == .stale { setStatus(.working) }
        case .permissionRequest:
            setStatus(.needsYou, detail: event.tool)
        case .notification:
            switch event.notificationType {
            case "permission_prompt", "elicitation_dialog":
                setStatus(.needsYou, detail: session.status == .needsYou ? session.detail : nil)
            case "idle_prompt":
                if session.status == .working || session.status == .stale { setStatus(.idle, detail: "Waiting for your next prompt") }
            default: break
            }
        case .stop:
            guard fresh else { break }
            if let started = session.turnStartedAt { session.lastTurnDuration = max(0, at.timeIntervalSince(started)) }
            session.turnStartedAt = nil
            setStatus(.finished)
            session.replyPath = event.replyTo
            finishRunningTools(&session)
            if let message = event.message { session.lastMessage = message; session.lastMessageAt = at; session.lastMessageIsError = false }
        case .stopFailure:
            guard fresh else { break }
            session.turnStartedAt = nil
            session.turnError = event.error ?? "unknown"
            setStatus(.finished, detail: event.error)
            finishRunningTools(&session)
            if let message = event.message { session.lastMessage = message; session.lastMessageAt = at; session.lastMessageIsError = true }
        case .interrupt:
            guard fresh else { break }
            session.turnStartedAt = nil
            // An interrupted turn did not finish; it is waiting on the person again.
            setStatus(.idle, detail: "Interrupted")
            finishRunningTools(&session)
        case .sessionEnd:
            break
        }
        sessions[index] = session
    }

    private func makeSession(key: String, event: AgentEvent, at: Date) -> AgentSession {
        let usedSlots = Set(sessions.compactMap(\.slot))
        let usedCoats = Set(sessions.map(\.coat))
        let coat = (0..<Self.coatCount).first { !usedCoats.contains($0) } ?? (sessions.count % Self.coatCount)
        return AgentSession(id: key, client: event.client, sessionID: event.sid,
                            slot: (1...9).first { !usedSlots.contains($0) }, coat: coat, createdAt: at,
                            statusSince: at, lastEventAt: at, statusStamp: 0)
    }

    private mutating func trimToLimit(adding count: Int) {
        while sessions.count + count > Self.maximumSessions {
            let victim = sessions.min { ($0.status.priority, $0.lastEventAt) < ($1.status.priority, $1.lastEventAt) }
            guard let victim else { return }
            sessions.removeAll { $0.id == victim.id }
        }
    }

    private func recordTool(_ event: AgentEvent, at: Date, in session: inout AgentSession) {
        // Late deliveries from a previous turn do not pollute this turn's counts.
        guard event.ts >= session.turnStamp, let name = event.tool else { return }
        var groupIndex = session.tools.firstIndex { $0.name == name }
        if groupIndex == nil {
            session.tools.append(AgentToolGroup(name: name, lastEventAt: at, order: session.nextToolOrder))
            session.nextToolOrder += 1
            groupIndex = session.tools.count - 1
        }
        guard let groupIndex else { return }
        var group = session.tools[groupIndex]
        group.lastEventAt = max(group.lastEventAt, at)
        let completed = event.event != .preToolUse
        let failed = event.event == .postToolUseFailure
        if let id = event.toolUseID {
            switch (session.toolCalls[id], completed) {
            case (nil, false):
                // Started: one attempt, running until its completion arrives.
                guard session.toolCalls.count < Self.maximumToolCallsPerTurn else { break }
                session.toolCalls[id] = false
                group.attempts += 1; group.running += 1
                if event.agentID != nil { group.fromSubagents += 1 }
            case (nil, true):
                // Completion arrived before its start (async hooks): count it once, as done.
                guard session.toolCalls.count < Self.maximumToolCallsPerTurn else { break }
                session.toolCalls[id] = true
                group.attempts += 1
                if failed { group.failures += 1 }
                if event.agentID != nil { group.fromSubagents += 1 }
            case (false?, true):
                session.toolCalls[id] = true
                group.running = max(0, group.running - 1)
                if failed { group.failures += 1 }
            default:
                break // Duplicate start, or a start after its completion.
            }
        } else if completed {
            // Without a call ID only completions count, so a start and finish are never doubled.
            group.attempts += 1
            if failed { group.failures += 1 }
            if event.agentID != nil { group.fromSubagents += 1 }
        }
        session.tools[groupIndex] = group
    }

    private func finishRunningTools(_ session: inout AgentSession) {
        for index in session.tools.indices { session.tools[index].running = 0 }
    }

    // MARK: Time

    /// Applies the stale and removal policy. Returns whether anything changed.
    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        let before = sessions
        sessions.removeAll { session in
            let quiet = now.timeIntervalSince(session.lastEventAt)
            switch session.status {
            case .idle, .finished: return quiet >= Self.quietRemoval
            case .stale: return quiet >= Self.staleRemoval
            case .working, .needsYou: return quiet >= Self.staleRemoval
            }
        }
        for index in sessions.indices where [.working, .needsYou].contains(sessions[index].status) {
            if now.timeIntervalSince(sessions[index].lastEventAt) >= Self.staleAfter {
                sessions[index].status = .stale
                sessions[index].statusSince = now
                sessions[index].detail = nil
            }
        }
        return before != sessions
    }

    /// When `expire` next has something to do, so the owner can schedule one wake-up instead of polling.
    public func nextDeadline() -> Date? {
        sessions.map { session -> Date in
            switch session.status {
            case .idle, .finished: return session.lastEventAt.addingTimeInterval(Self.quietRemoval)
            case .working, .needsYou: return session.lastEventAt.addingTimeInterval(Self.staleAfter)
            case .stale: return session.lastEventAt.addingTimeInterval(Self.staleRemoval)
            }
        }.min()
    }

    public mutating func removeAll() { sessions.removeAll() }

    /// A copy without the given sessions (dismissed from the island but still observed).
    public func excluding(_ ids: Set<String>) -> AgentActivityStore {
        guard !ids.isEmpty else { return self }
        var copy = self
        copy.sessions.removeAll { ids.contains($0.id) }
        return copy
    }

    /// Forgets sessions that are not working or waiting on the person.
    public mutating func removeInactive() {
        sessions.removeAll { [.finished, .idle, .stale].contains($0.status) }
    }

    /// After a reply was sent (or the relay is gone), the turn can no longer be answered here.
    public mutating func clearReply(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].replyPath = nil
    }
}

/// Reads the repository name and current branch for a working directory: at most a few small
/// files, walking up from `cwd`. No git process, no history, nothing outside the repository's own metadata.
public enum AgentProjectResolver {
    public static func resolve(_ cwd: String) -> (project: String?, branch: String?) {
        var url = URL(fileURLWithPath: cwd).standardizedFileURL
        let fallback = url.lastPathComponent.isEmpty ? nil : url.lastPathComponent
        for _ in 0..<24 {
            let dotGit = url.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                var gitDirectory = dotGit
                if !isDirectory.boolValue {
                    // A worktree or submodule: ".git" is a file naming the real git directory.
                    guard let text = smallText(dotGit), let line = text.split(separator: "\n").first,
                          line.hasPrefix("gitdir:") else { return (url.lastPathComponent, nil) }
                    let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    gitDirectory = path.hasPrefix("/") ? URL(fileURLWithPath: path) : url.appendingPathComponent(path)
                }
                return (url.lastPathComponent, branch(fromHead: smallText(gitDirectory.appendingPathComponent("HEAD"))))
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return (fallback, nil)
    }

    static func branch(fromHead head: String?) -> String? {
        guard let head = head?.trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty else { return nil }
        if head.hasPrefix("ref: refs/heads/") {
            let name = String(head.dropFirst("ref: refs/heads/".count))
            return name.isEmpty || name.count > 200 ? nil : name
        }
        // Detached HEAD: a commit hash.
        if head.count >= 7, head.allSatisfy(\.isHexDigit) { return String(head.prefix(7)) }
        return nil
    }

    private static func smallText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
