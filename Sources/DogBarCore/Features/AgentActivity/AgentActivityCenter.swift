import AppKit
import Combine
import Foundation

/// Owns live observation and the demo, and publishes what the island shows.
/// Live and demo state are separate stores: demo sessions can never appear as live ones.
@MainActor public final class AgentActivityCenter: ObservableObject {
    public enum Source: Equatable { case live, demo }
    public enum Connection: Equatable {
        case off, listening, failed(AgentEventListener.Failure)
    }
    public struct LastEvent: Equatable {
        public let client: AgentClient
        public let kind: AgentEvent.Kind
        public let receivedAt: Date
    }

    /// What the island renders: the live store, or the demo store while a demo runs.
    @Published public private(set) var displayed = AgentActivityStore()
    @Published public private(set) var source: Source = .live
    @Published public private(set) var connection: Connection = .off
    @Published public private(set) var lastEvent: LastEvent?
    @Published public private(set) var lastEventByClient: [AgentClient: Date] = [:]
    @Published public private(set) var counters = AgentEventListener.Counters()
    /// The session shown in the open island. Survives updates; only explicit choice or removal changes it.
    @Published public private(set) var selectedID: String?
    /// The open island shows the list of all sessions instead of one session.
    @Published public private(set) var showingList = false
    /// The app each session runs in, when it could be found.
    @Published public private(set) var hosts: [String: AgentHostApp] = [:]
    /// Unsent reply text per session, kept while the island closes and reopens.
    @Published public var drafts: [String: String] = [:]
    /// Outcome of the last reply per session.
    @Published public private(set) var replyNotes: [String: ReplyNote] = [:]
    public enum ReplyNote: Equatable { case sent(Date), expired }
    /// When the person last looked at each session in the open island.
    @Published public private(set) var seen: [String: Date] = [:]
    /// Sessions hidden from the island. Still observed; they return on a new turn or when they need the person.
    @Published public private(set) var dismissed: Set<String> = []
    public enum Attention: Equatable { case needsYou, failed, unseen }
    /// Plays a cue for live (and demo) transitions when set.
    public var sounds: AgentSounds?
    public var soundsEnabled: () -> Bool = { false }
    /// Whether the person wants to reply from the island (Settings › Beta). Used to explain a missing reply field.
    public var repliesWanted: () -> Bool = { false }
    /// Claude Code sent a Stop without a reply channel: its hooks predate replies or have replies turned off.
    @Published public private(set) var claudeHooksLackReplies = false

    private var live = AgentActivityStore(resolveProject: { AgentProjectResolver.resolve($0) })
    private var demo = AgentActivityStore()
    private let listener: AgentEventListener
    private var publishTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    /// Ordinary count updates are coalesced; urgent ones (needs you, errors, ends) publish at once.
    static let coalesceInterval: Duration = .milliseconds(140)

    public init(listener: AgentEventListener? = nil) {
        let listener = listener ?? AgentEventListener()
        self.listener = listener
        listener.onEvent = { [weak self] event in self?.receive(event) }
        listener.onChange = { [weak self] in self?.counters = listener.counters }
    }

    public var socketPath: String { listener.url.path }
    public var isEnabled: Bool { listener.isListening }

    // MARK: Lifecycle

    /// Starts or stops live observation. Turning it off forgets live sessions.
    public func setEnabled(_ enabled: Bool) {
        if enabled {
            guard !listener.isListening else { return }
            do {
                try listener.start()
                AgentReplyChannel.removeStale(in: listener.url.deletingLastPathComponent())
                connection = .listening
            } catch {
                connection = .failed(error)
            }
        } else {
            let wasActive = listener.isListening || connection != .off
            listener.stop()
            connection = .off
            guard wasActive else { return }
            for path in live.sessions.compactMap(\.replyPath) { AgentReplyChannel.send(.init(action: .cancel), to: path) }
            live.removeAll()
            hosts = [:]; drafts = [:]; replyNotes = [:]; seen = [:]; dismissed = []
            expiryTask?.cancel(); expiryTask = nil
            if source == .live { publishNow() }
        }
    }

    /// Retry after a failure, for example after quitting another DogBar.
    public func retry() {
        guard case .failed = connection else { return }
        connection = .off
        setEnabled(true)
    }

    func receive(_ event: AgentEvent) {
        var event = event
        // Reply sockets must live next to DogBar's own event socket.
        if let path = event.replyTo, URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
            != listener.url.deletingLastPathComponent().standardizedFileURL { event.replyTo = nil }
        let key = AgentActivityStore.key(event.client, event.sid)
        if event.client == .claude, event.event == .stop {
            let lacking = event.replyTo == nil
            if claudeHooksLackReplies != lacking { claudeHooksLackReplies = lacking }
        }
        let previous = live.session(key)
        live.apply(event)
        let updated = live.session(key)
        // A dismissed session comes back when a new turn starts or it needs the person.
        if dismissed.contains(key), event.event == .userPromptSubmit || (updated?.status == .needsYou && previous?.status != .needsYou) {
            dismissed.remove(key)
        }
        if updated == nil { dismissed.remove(key); seen[key] = nil }
        // A relay still waiting on an older turn is released (the person typed in the terminal, or the session moved on).
        if let old = previous?.replyPath, updated?.replyPath != old { AgentReplyChannel.send(.init(action: .cancel), to: old) }
        if let updated, let pid = updated.hostPID, hosts[key]?.pidSource != pid {
            if let host = AgentHostApp.resolve(from: pid) { hosts[key] = host.withSource(pid) } else { hosts[key] = nil }
        }
        if updated == nil { hosts[key] = nil; drafts[key] = nil; replyNotes[key] = nil }
        if source == .live, !dismissed.contains(key) { cue(from: previous, to: updated) }
        lastEvent = LastEvent(client: event.client, kind: event.event, receivedAt: Date())
        lastEventByClient[event.client] = Date()
        let current = updated
        let urgent = previous == nil || current == nil || previous?.status != current?.status || previous?.replyPath != current?.replyPath
        scheduleExpiry()
        guard source == .live else { return }
        if urgent { publishNow() } else { schedulePublish() }
    }

    private func cue(from previous: AgentSession?, to current: AgentSession?) {
        guard soundsEnabled(), let sounds, let current, previous?.status != current.status || previous?.statusStamp != current.statusStamp else { return }
        guard previous?.status != current.status else { return }
        switch current.status {
        case .needsYou: sounds.play(.needsYou)
        case .finished: sounds.play(current.turnError == nil ? .finished : .failed)
        default: break
        }
    }

    // MARK: Replies

    /// Sends a reply to the waiting relay of a finished Claude Code turn. Returns false if it is gone.
    @discardableResult
    public func sendReply(to id: String, text: String) -> Bool {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentReplyChannel.maximumReply))
        guard !trimmed.isEmpty, source == .live, let path = live.session(id)?.replyPath else { return false }
        let sent = AgentReplyChannel.send(.init(action: .reply, text: trimmed), to: path)
        live.clearReply(id)
        replyNotes[id] = sent ? .sent(Date()) : .expired
        if sent { drafts[id] = nil }
        publishNow()
        return sent
    }

    /// Brings forward the app the session runs in.
    @discardableResult
    public func openHost(of id: String) -> Bool { hosts[id]?.activate() ?? false }

    /// Hides one session from the island until it starts a new turn or needs the person.
    public func dismiss(_ id: String) {
        if source == .demo {
            demo = demo.excluding([id])
        } else {
            if let path = live.session(id)?.replyPath { AgentReplyChannel.send(.init(action: .cancel), to: path); live.clearReply(id) }
            dismissed.insert(id)
        }
        drafts[id] = nil
        if selectedID == id { selectedID = nil; showingList = displayed.sessions.count > 1 }
        publishNow()
        if selectedID == nil, !showingList { selectedID = displayed.lead?.id }
    }

    /// The person looked at this session in the open island.
    public func markSeen(_ id: String) { seen[id] = Date() }

    /// What a session's dot should flag: it needs you, its turn failed, or it finished since you last looked.
    public func attention(for session: AgentSession) -> Attention? {
        if session.status == .needsYou { return .needsYou }
        guard session.status == .finished else { return nil }
        let unseen = (seen[session.id] ?? .distantPast) < session.statusSince
        guard unseen else { return nil }
        return session.turnError == nil ? .unseen : .failed
    }

    /// Forgets finished, idle and stale sessions.
    public func clearInactive() {
        if source == .demo { demo.removeInactive() } else {
            for session in live.sessions where [.finished, .idle, .stale].contains(session.status) {
                if let path = session.replyPath { AgentReplyChannel.send(.init(action: .cancel), to: path) }
            }
            live.removeInactive()
        }
        publishNow()
    }

    private func schedulePublish() {
        guard publishTask == nil else { return }
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coalesceInterval)
            guard !Task.isCancelled else { return }
            self?.publishNow()
        }
    }

    private func publishNow() {
        publishTask?.cancel(); publishTask = nil
        let store = source == .demo ? demo : live.excluding(dismissed)
        if displayed != store { displayed = store }
        if let selectedID, store.session(selectedID) == nil { self.selectedID = neighbor(of: selectedID) }
        if store.sessions.isEmpty { showingList = false }
    }

    private var lastOrder: [String] = []
    private func neighbor(of id: String) -> String? {
        let ordered = displayed.ordered.map(\.id)
        defer { lastOrder = ordered }
        guard let old = lastOrder.firstIndex(of: id) else { return ordered.first }
        return lastOrder[..<old].reversed().first { ordered.contains($0) } ?? lastOrder[(old + 1)...].first { ordered.contains($0) } ?? ordered.first
    }

    /// One wake-up at the next stale/removal deadline. No periodic timer.
    private func scheduleExpiry() {
        expiryTask?.cancel(); expiryTask = nil
        guard let deadline = live.nextDeadline() else { return }
        expiryTask = Task { [weak self] in
            let delay = max(1, deadline.timeIntervalSinceNow + 0.5)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if self.live.expire(now: Date()), self.source == .live { self.publishNow() }
            self.scheduleExpiry()
        }
    }

    // MARK: Selection

    /// Picks the session the island should open on: keeps the current one, else the most urgent.
    public func prepareSelection() {
        lastOrder = displayed.ordered.map(\.id)
        // A session that needs the person opens directly; otherwise keep where they were.
        if let urgent = displayed.ordered.first(where: { $0.status == .needsYou }) { selectedID = urgent.id; showingList = false; return }
        if showingList { return }
        if let selectedID, displayed.session(selectedID) != nil { return }
        if displayed.sessions.count > 1 { showingList = true } else { selectedID = displayed.lead?.id }
    }
    public func select(_ id: String) {
        guard displayed.session(id) != nil else { return }
        selectedID = id
        showingList = false
        lastOrder = displayed.ordered.map(\.id)
    }
    public func showList() {
        guard !displayed.sessions.isEmpty else { return }
        showingList = true
    }
    public func select(slot: Int) {
        if let session = displayed.sessions.first(where: { $0.slot == slot }) { select(session.id) }
    }
    /// Arrows step through pages: the session list, then each session in dot order, wrapping around.
    public func selectAdjacent(_ delta: Int) {
        let pages: [String?] = [nil] + displayed.ordered.map { Optional($0.id) }
        guard pages.count > 1 else { return }
        let current = showingList ? 0 : (pages.firstIndex { $0 == selectedID } ?? 0)
        let next = pages[(current + delta + pages.count) % pages.count]
        if let next { select(next) } else { showList() }
    }

    // MARK: Demo

    public var isDemoRunning: Bool { source == .demo }

    /// Plays a scripted, clearly labeled simulation through the same store logic, without the socket.
    public func startDemo() {
        demoTask?.cancel()
        demo = AgentActivityStore()
        source = .demo
        selectedID = nil
        showingList = false
        publishNow()
        demoTask = Task { [weak self] in
            let start = Date()
            for step in AgentActivityDemo.script {
                let target = start.addingTimeInterval(step.at)
                let wait = target.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self, self.source == .demo else { return }
                var event = step.event
                event.ts = Date().timeIntervalSince1970 + step.skew
                let previous = self.demo.session(AgentActivityStore.key(event.client, event.sid))
                self.demo.apply(event)
                self.cue(from: previous, to: self.demo.session(AgentActivityStore.key(event.client, event.sid)))
                if self.selectedID == nil { self.selectedID = self.demo.lead?.id }
                self.publishNow()
            }
        }
    }

    public func stopDemo() {
        guard source == .demo else { return }
        demoTask?.cancel(); demoTask = nil
        demo = AgentActivityStore()
        source = .live
        selectedID = nil
        showingList = false
        publishNow()
    }
}

/// The demo timeline: two sessions with different needs, tool bursts, a failure, a permission
/// prompt, a duplicate and an out-of-order event, then a finished and an idle session.
enum AgentActivityDemo {
    struct Step {
        let at: TimeInterval
        var event: AgentEvent
        /// Seconds added to the event's hook time, to replay late or out-of-order delivery.
        var skew: TimeInterval = 0
    }
    static let script: [Step] = {
        typealias E = AgentEvent
        func e(_ client: AgentClient, _ kind: E.Kind, _ sid: String, cwd: String? = nil, tool: String? = nil, id: String? = nil,
               message: String? = nil, notification: String? = nil, title: String? = nil, model: String? = nil, error: String? = nil) -> E {
            E(client: client, event: kind, sid: sid, ts: 0, cwd: cwd, tool: tool, toolUseID: id, notificationType: notification,
              message: message, title: title, model: model, error: error)
        }
        let a = "demo-garden", b = "demo-api", c = "demo-docs"
        var steps: [Step] = [
            Step(at: 0.2, event: e(.claude, .sessionStart, a, cwd: "/Demo/garden-planner", title: "Demo: tidy the planting calendar")),
            Step(at: 0.9, event: e(.claude, .userPromptSubmit, a, cwd: "/Demo/garden-planner")),
            Step(at: 1.6, event: e(.codex, .sessionStart, b, cwd: "/Demo/weather-api", model: "demo-model")),
        ]
        var t = 1.4
        for (index, tool) in ["Read", "Read", "Grep", "Read", "Edit", "Bash", "Bash", "Edit", "Bash"].enumerated() {
            let id = "a\(index)"
            steps.append(Step(at: t, event: e(.claude, .preToolUse, a, tool: tool, id: id)))
            let failed = index == 6
            steps.append(Step(at: t + 0.35, event: e(.claude, failed ? .postToolUseFailure : .postToolUse, a, tool: tool, id: id)))
            t += 0.45
        }
        // A duplicate completion: must not count twice.
        steps.append(Step(at: t, event: e(.claude, .postToolUse, a, tool: "Bash", id: "a8")))
        steps += [
            Step(at: 2.6, event: e(.codex, .userPromptSubmit, b, cwd: "/Demo/weather-api")),
            Step(at: 3.1, event: e(.codex, .preToolUse, b, tool: "shell", id: "b1")),
            Step(at: 3.5, event: e(.codex, .postToolUse, b, tool: "shell", id: "b1")),
            Step(at: 4.4, event: e(.codex, .permissionRequest, b, tool: "shell")),
            // A late Stop from before the prompt: older than current status, so it is ignored.
            Step(at: 5.0, event: e(.codex, .stop, b, message: "This stale reply must not appear."), skew: -30),
            Step(at: 6.2, event: e(.claude, .sessionStart, c, cwd: "/Demo/handbook")),
            Step(at: t + 0.6, event: e(.claude, .stop, a, message: "Moved the frost dates into one table and fixed the tests that read them. One shell command failed once and passed on retry.")),
            Step(at: 9.0, event: e(.codex, .preToolUse, b, tool: "shell", id: "b2")),
            Step(at: 9.6, event: e(.codex, .postToolUse, b, tool: "shell", id: "b2")),
            Step(at: 10.4, event: e(.codex, .preToolUse, b, tool: "apply_patch", id: "b3")),
            Step(at: 10.9, event: e(.codex, .postToolUse, b, tool: "apply_patch", id: "b3")),
            Step(at: 12.0, event: e(.codex, .stop, b, message: "Added the retry policy and a test for the timeout path.")),
        ]
        return steps.sorted { $0.at < $1.at }
    }()
}
