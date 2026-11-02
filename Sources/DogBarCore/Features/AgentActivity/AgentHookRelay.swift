import Foundation

/// The hook command. `DogBar --agent-hook claude|codex` reads one hook payload from stdin, keeps
/// only the fields DogBar displays, sends them to the running app and exits 0. It never prints a
/// permission decision or blocks: when DogBar is not running the event is silently dropped.
public enum AgentHookRelay {
    public static let argument = "--agent-hook"
    /// Hook payloads larger than this (huge prompts or tool inputs) are drained and ignored.
    static let maximumInput = 8 * 1024 * 1024

    /// Returns the exit code. Called from `main` before any AppKit setup.
    public static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let name = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        guard let client = AgentClient(rawValue: name) else { return 0 }
        let replies = arguments.contains(AgentReplyChannel.argument) && client == .claude
        let input = readInput(FileHandle.standardInput)
        var hookName: String?
        if let input, var event = event(fromHookJSON: input, client: client, now: Date()) {
            hookName = event.event.rawValue
            event.hostPID = getppid()
            // Replies: only for Stop, only when DogBar received the event. Otherwise exit at once.
            if replies, event.event == .stop,
               let waiter = AgentReplyChannel.Waiter(directory: AgentEventSocket.defaultURL.deletingLastPathComponent()) {
                event.replyTo = waiter.url.path
                guard let data = event.encoded(), AgentEventSocket.send(data) else { return 0 }
                if let message = waiter.wait(timeout: AgentReplyChannel.waitLimit), message.action == .reply, let text = message.text {
                    FileHandle.standardError.write(Data(AgentReplyChannel.wakeText(text).utf8))
                    return 2
                }
                return 0
            }
            if let data = event.encoded() { AgentEventSocket.send(data) }
        } else if let input, let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
            hookName = object["hook_event_name"] as? String
        }
        if let output = standardOutput(client: client, hookEventName: hookName) {
            FileHandle.standardOutput.write(Data(output.utf8))
        }
        return 0
    }

    /// Codex requires JSON on stdout for Stop and SubagentStop. An empty object makes no decision.
    /// Everything else gets no output at all, so nothing is added to the conversation.
    public static func standardOutput(client: AgentClient, hookEventName: String?) -> String? {
        guard client == .codex, hookEventName == "Stop" || hookEventName == "SubagentStop" else { return nil }
        return "{}\n"
    }

    static func readInput(_ handle: FileHandle) -> Data? {
        var data = Data()
        var overflow = false
        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { break }
            // Keep draining so the writer never sees a broken pipe, but stop storing.
            if !overflow {
                data.append(chunk)
                if data.count > maximumInput { overflow = true; data = Data() }
            }
        }
        return overflow || data.isEmpty ? nil : data
    }

    /// Maps a client's documented hook JSON to an event, or nil for events DogBar does not show.
    public static func event(fromHookJSON data: Data, client: AgentClient, now: Date) -> AgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["hook_event_name"] as? String, let kind = AgentEvent.Kind(rawValue: name),
              let sid = object["session_id"] as? String else { return nil }
        func string(_ key: String) -> String? { object[key] as? String }
        var event = AgentEvent(client: client, event: kind, sid: sid, ts: now.timeIntervalSince1970)
        event.cwd = string("cwd")
        event.agentID = string("agent_id")
        event.agentType = string("agent_type")
        event.model = string("model")
        event.title = string("session_title")
        switch kind {
        case .preToolUse, .postToolUse, .postToolUseFailure, .permissionRequest:
            event.tool = string("tool_name")
            event.toolUseID = string("tool_use_id")
        case .notification:
            event.notificationType = string("notification_type")
            event.message = string("message")
        case .stop:
            event.message = string("last_assistant_message")
        case .stopFailure:
            event.error = string("error")
            event.message = string("last_assistant_message")
        case .sessionStart:
            event.reason = string("source")
        case .sessionEnd:
            event.reason = string("reason")
        case .userPromptSubmit:
            // Only what the person typed (or replied from the island), never internal notification markup.
            if let shown = AgentPromptText.display(string("prompt")) {
                event.prompt = shown.text
                event.promptViaDogBar = shown.viaDogBar ? true : nil
            }
        case .interrupt:
            break
        }
        return try? event.validated()
    }
}

/// Turns a client's raw prompt into what a person would recognise as their own words.
/// Claude Code reports some turns it starts itself (hook feedback, background task notifications)
/// through UserPromptSubmit with internal markup; those are not the person's prompt.
public enum AgentPromptText {
    public struct Display: Equatable, Sendable {
        public let text: String
        /// The text was a reply sent from DogBar's island.
        public let viaDogBar: Bool
    }

    static let dogBarMarker = "(treat this as their next message):"
    static let internalTags = ["<task-notification>", "<system-reminder>", "<local-command-stdout>", "<local-command-caveat>", "<bash-stdout>", "<bash-input>"]

    public static func display(_ raw: String?) -> Display? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains("replied from DogBar"), let range = raw.range(of: dogBarMarker) {
            var reply = String(raw[range.upperBound...])
            if let end = reply.range(of: "</system-reminder>") { reply = String(reply[..<end.lowerBound]) }
            reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return reply.isEmpty ? nil : Display(text: reply, viaDogBar: true)
        }
        // Slash commands: "<command-name>/review</command-name> … <command-args>main</command-args>".
        if let name = tagContent("command-name", in: raw) {
            let args = tagContent("command-args", in: raw) ?? ""
            let command = name.hasPrefix("/") ? name : "/\(name)"
            return Display(text: args.isEmpty ? command : "\(command) \(args)", viaDogBar: false)
        }
        // Turns Claude Code started on its own, not something the person typed.
        if internalTags.contains(where: { raw.hasPrefix($0) }) || raw.hasPrefix("[SYSTEM NOTIFICATION") { return nil }
        return Display(text: raw, viaDogBar: false)
    }

    static func tagContent(_ tag: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(tag)>"), let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex) else { return nil }
        let value = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
