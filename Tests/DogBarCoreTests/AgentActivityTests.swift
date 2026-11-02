import SwiftUI
import XCTest
@testable import DogBarCore

final class AgentEventTests: XCTestCase {
    private let now = 1_790_000_000.0

    func testRoundTripAndValidation() throws {
        let event = AgentEvent(client: .claude, event: .stop, sid: "abc-123_x.y:z", ts: now, cwd: "/tmp/p", message: "Done")
        let decoded = try AgentEvent.decode(XCTUnwrap(event.encoded()))
        XCTAssertEqual(decoded, event)
    }

    func testRejectsMalformedOversizeAndUnsupported() {
        XCTAssertThrowsError(try AgentEvent.decode(Data("not json".utf8))) { XCTAssertEqual($0 as? AgentEvent.ValidationError, .malformed) }
        XCTAssertThrowsError(try AgentEvent.decode(Data(repeating: 0x20, count: AgentEvent.maximumWireSize + 1))) {
            XCTAssertEqual($0 as? AgentEvent.ValidationError, .tooLarge)
        }
        let unknownKind = #"{"v":1,"client":"claude","event":"Bogus","sid":"a","ts":1790000000}"#
        XCTAssertThrowsError(try AgentEvent.decode(Data(unknownKind.utf8)))
        let unknownClient = #"{"v":1,"client":"other","event":"Stop","sid":"a","ts":1790000000}"#
        XCTAssertThrowsError(try AgentEvent.decode(Data(unknownClient.utf8)))
        let version = #"{"v":2,"client":"claude","event":"Stop","sid":"a","ts":1790000000}"#
        XCTAssertThrowsError(try AgentEvent.decode(Data(version.utf8))) { XCTAssertEqual($0 as? AgentEvent.ValidationError, .unsupportedVersion) }
        let badSession = #"{"v":1,"client":"claude","event":"Stop","sid":"../../etc","ts":1790000000}"#
        XCTAssertThrowsError(try AgentEvent.decode(Data(badSession.utf8))) { XCTAssertEqual($0 as? AgentEvent.ValidationError, .invalidSession) }
        let badTime = #"{"v":1,"client":"claude","event":"Stop","sid":"a","ts":12}"#
        XCTAssertThrowsError(try AgentEvent.decode(Data(badTime.utf8))) { XCTAssertEqual($0 as? AgentEvent.ValidationError, .invalidTimestamp) }
    }

    func testCleansControlCharactersAndClampsText() throws {
        var event = AgentEvent(client: .codex, event: .stop, sid: "s", ts: now)
        event.tool = "Ba\u{0}sh\u{202E}\n"
        event.message = String(repeating: "x", count: 5000) + "\u{7}"
        event.title = "line\nbreak"
        let clean = try event.validated()
        XCTAssertEqual(clean.tool, "Bash")
        XCTAssertEqual(clean.title, "line break")
        XCTAssertEqual(clean.message?.count, AgentEvent.Limit.message)
        XCTAssertTrue(clean.message?.hasSuffix("…") == true)
        event.message = "   \n  "
        XCTAssertNil(try event.validated().message)
    }
}

final class AgentHookRelayTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    func testClaudePermissionRequestKeepsToolNameButNotInput() throws {
        let json = #"{"session_id":"abc123","cwd":"/Users/x/p","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf secret"},"permission_mode":"default"}"#
        let event = try XCTUnwrap(AgentHookRelay.event(fromHookJSON: Data(json.utf8), client: .claude, now: date))
        XCTAssertEqual(event.event, .permissionRequest)
        XCTAssertEqual(event.tool, "Bash")
        XCTAssertEqual(event.cwd, "/Users/x/p")
        let wire = String(decoding: try XCTUnwrap(event.encoded()), as: UTF8.self)
        XCTAssertFalse(wire.contains("secret"))
    }

    func testPromptIsForwardedClampedAndToolInputIsNot() throws {
        let long = String(repeating: "p", count: 1000)
        let json = #"{"session_id":"s","cwd":"/p","hook_event_name":"UserPromptSubmit","prompt":"\#(long)","session_title":"Fix login"}"#
        let event = try XCTUnwrap(AgentHookRelay.event(fromHookJSON: Data(json.utf8), client: .claude, now: date))
        XCTAssertEqual(event.title, "Fix login")
        XCTAssertEqual(event.prompt?.count, AgentEvent.Limit.prompt)
    }

    func testStopCarriesLastAssistantMessageAndSubagentFieldsSurvive() throws {
        let json = #"{"session_id":"s","hook_event_name":"Stop","last_assistant_message":"All done.","stop_hook_active":false}"#
        XCTAssertEqual(AgentHookRelay.event(fromHookJSON: Data(json.utf8), client: .claude, now: date)?.message, "All done.")
        let tool = #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Read","tool_use_id":"t1","agent_id":"def456","agent_type":"Explore"}"#
        let event = try XCTUnwrap(AgentHookRelay.event(fromHookJSON: Data(tool.utf8), client: .claude, now: date))
        XCTAssertEqual(event.agentID, "def456")
        XCTAssertEqual(event.toolUseID, "t1")
    }

    func testIgnoresUnsupportedOrBrokenPayloads() {
        XCTAssertNil(AgentHookRelay.event(fromHookJSON: Data(#"{"session_id":"s","hook_event_name":"PreCompact"}"#.utf8), client: .codex, now: date))
        XCTAssertNil(AgentHookRelay.event(fromHookJSON: Data(#"{"hook_event_name":"Stop"}"#.utf8), client: .codex, now: date))
        XCTAssertNil(AgentHookRelay.event(fromHookJSON: Data("[]".utf8), client: .codex, now: date))
    }

    func testOnlyCodexStopGetsJSONOutputAndItMakesNoDecision() {
        XCTAssertEqual(AgentHookRelay.standardOutput(client: .codex, hookEventName: "Stop"), "{}\n")
        XCTAssertNil(AgentHookRelay.standardOutput(client: .codex, hookEventName: "PermissionRequest"))
        XCTAssertNil(AgentHookRelay.standardOutput(client: .claude, hookEventName: "Stop"))
        XCTAssertNil(AgentHookRelay.standardOutput(client: .claude, hookEventName: "PermissionRequest"))
        XCTAssertNil(AgentHookRelay.standardOutput(client: .codex, hookEventName: nil))
    }

    func testNotRequestedWithoutArgument() {
        XCTAssertNil(AgentHookRelay.runIfRequested(arguments: ["DogBar"]))
    }
}

final class AgentActivityStoreTests: XCTestCase {
    private let t0 = 1_790_000_000.0
    private func event(_ kind: AgentEvent.Kind, _ sid: String = "a", at offset: Double, client: AgentClient = .claude,
                       tool: String? = nil, id: String? = nil, agent: String? = nil, message: String? = nil,
                       notification: String? = nil, error: String? = nil) -> AgentEvent {
        AgentEvent(client: client, event: kind, sid: sid, ts: t0 + offset, cwd: "/work/\(sid)", tool: tool, toolUseID: id,
                   agentID: agent, notificationType: notification, message: message, error: error)
    }
    private func store(_ events: [AgentEvent]) -> AgentActivityStore {
        var store = AgentActivityStore()
        events.forEach { store.apply($0) }
        return store
    }

    func testTurnLifecycle() throws {
        let s = store([event(.sessionStart, at: 0), event(.userPromptSubmit, at: 1)])
        XCTAssertEqual(s.sessions.first?.status, .working)
        XCTAssertEqual(s.sessions.first?.project, "a")
        var done = s
        done.apply(event(.stop, at: 31, message: "Finished."))
        let session = try XCTUnwrap(done.sessions.first)
        XCTAssertEqual(session.status, .finished)
        XCTAssertEqual(session.lastMessage, "Finished.")
        XCTAssertEqual(try XCTUnwrap(session.lastTurnDuration), 30, accuracy: 0.001)
        XCTAssertNil(session.turnStartedAt)
    }

    func testToolCallsDeduplicatedByIDWithFailuresAsSubset() throws {
        let s = store([
            event(.userPromptSubmit, at: 0),
            event(.preToolUse, at: 1, tool: "Bash", id: "1"), event(.postToolUse, at: 2, tool: "Bash", id: "1"),
            // Completion before start (async delivery) and a duplicate completion.
            event(.postToolUseFailure, at: 4, tool: "Bash", id: "2"), event(.preToolUse, at: 3, tool: "Bash", id: "2"),
            event(.postToolUse, at: 5, tool: "Bash", id: "1"),
            event(.preToolUse, at: 6, tool: "Read", id: "3"),
            // No call ID: only the completion counts.
            event(.preToolUse, at: 7, tool: "Grep"), event(.postToolUse, at: 8, tool: "Grep"),
        ])
        let session = try XCTUnwrap(s.sessions.first)
        XCTAssertEqual(session.tools.map(\.name), ["Bash", "Read", "Grep"], "first-seen order is stable")
        let bash = try XCTUnwrap(session.tools.first { $0.name == "Bash" })
        XCTAssertEqual(bash.attempts, 2)
        XCTAssertEqual(bash.failures, 1)
        XCTAssertEqual(bash.running, 0)
        XCTAssertEqual(session.tools.first { $0.name == "Read" }?.running, 1)
        XCTAssertEqual(session.runningTool, "Read")
        XCTAssertEqual(session.tools.first { $0.name == "Grep" }?.attempts, 1)
        XCTAssertEqual(session.toolAttempts, 4)
        XCTAssertEqual(session.toolFailures, 1)
    }

    func testNewTurnResetsToolsAndIgnoresLateEventsFromPreviousTurn() throws {
        let s = store([
            event(.userPromptSubmit, at: 0), event(.postToolUse, at: 1, tool: "Read", id: "1"), event(.stop, at: 2),
            event(.userPromptSubmit, at: 10),
            event(.postToolUse, at: 1.5, tool: "Edit", id: "late"),
        ])
        XCTAssertEqual(s.sessions.first?.tools.count, 0)
        XCTAssertEqual(s.sessions.first?.status, .working)
    }

    func testPermissionThenToolActivityReturnsToWorking() throws {
        var s = store([event(.userPromptSubmit, at: 0), event(.permissionRequest, at: 1, tool: "Bash")])
        XCTAssertEqual(s.sessions.first?.status, .needsYou)
        XCTAssertEqual(s.sessions.first?.detail, "Bash")
        s.apply(event(.postToolUse, at: 5, tool: "Bash", id: "x"))
        XCTAssertEqual(s.sessions.first?.status, .working)
    }

    func testOutOfOrderStatusEventsCannotRollBack() {
        var s = store([event(.userPromptSubmit, at: 10)])
        s.apply(event(.stop, at: 5, message: "stale"))
        XCTAssertEqual(s.sessions.first?.status, .working)
        XCTAssertNil(s.sessions.first?.lastMessage)
        s.apply(event(.permissionRequest, at: 9))
        XCTAssertEqual(s.sessions.first?.status, .working)
    }

    func testInterruptIsNotFinishedAndFailureIsTyped() {
        var s = store([event(.userPromptSubmit, at: 0, client: .codex), event(.interrupt, at: 1, client: .codex)])
        XCTAssertEqual(s.sessions.first?.status, .idle)
        XCTAssertEqual(s.sessions.first?.detail, "Interrupted")
        XCTAssertNil(s.sessions.first?.lastTurnDuration)
        s.apply(event(.userPromptSubmit, at: 2, client: .codex))
        s.apply(event(.stopFailure, at: 3, client: .codex, message: "API Error: Rate limit reached", error: "rate_limit"))
        XCTAssertEqual(s.sessions.first?.status, .finished)
        XCTAssertEqual(s.sessions.first?.turnError, "rate_limit")
        XCTAssertEqual(s.sessions.first?.lastMessageIsError, true)
    }

    func testNotificationsMapOnlyDocumentedTypes() {
        var s = store([event(.userPromptSubmit, at: 0), event(.notification, at: 1, notification: "auth_success")])
        XCTAssertEqual(s.sessions.first?.status, .working)
        s.apply(event(.notification, at: 2, notification: "idle_prompt"))
        XCTAssertEqual(s.sessions.first?.status, .idle)
        s.apply(event(.notification, at: 3, notification: "permission_prompt"))
        XCTAssertEqual(s.sessions.first?.status, .needsYou)
    }

    func testSubagentToolsAreKeptButDoNotReopenAFinishedTurn() throws {
        let s = store([event(.userPromptSubmit, at: 0), event(.stop, at: 5),
                       event(.postToolUse, at: 6, tool: "Read", id: "sub", agent: "def456")])
        let session = try XCTUnwrap(s.sessions.first)
        XCTAssertEqual(session.status, .finished)
        XCTAssertTrue(session.sawSubagentEvents)
        XCTAssertEqual(session.tools.first?.fromSubagents, 1)
    }

    func testSlotsAndCoatsAreStableAndReused() {
        var s = store([event(.sessionStart, "a", at: 0), event(.sessionStart, "b", at: 1), event(.sessionStart, "c", at: 2)])
        XCTAssertEqual(s.ordered.map(\.slot), [1, 2, 3])
        XCTAssertEqual(Set(s.sessions.map(\.coat)).count, 3)
        let coatC = s.session("claude:c")?.coat
        s.apply(event(.sessionEnd, "a", at: 3))
        s.apply(event(.userPromptSubmit, "c", at: 4))
        XCTAssertEqual(s.session("claude:c")?.slot, 3, "activity never reshuffles slots")
        XCTAssertEqual(s.session("claude:c")?.coat, coatC)
        s.apply(event(.sessionStart, "d", at: 5))
        XCTAssertEqual(s.session("claude:d")?.slot, 1)
        XCTAssertEqual(s.ordered.map(\.sessionID), ["d", "b", "c"])
    }

    func testSameSessionIDFromDifferentClientsIsSeparate() {
        let s = store([event(.sessionStart, "x", at: 0), event(.sessionStart, "x", at: 0, client: .codex)])
        XCTAssertEqual(s.sessions.count, 2)
    }

    func testSessionCountIsBoundedAndSlotsStopAtNine() {
        var s = AgentActivityStore()
        for index in 0..<30 { s.apply(event(.sessionStart, "s\(index)", at: Double(index))) }
        XCTAssertEqual(s.sessions.count, AgentActivityStore.maximumSessions)
        XCTAssertEqual(s.sessions.compactMap(\.slot).count, 9)
        XCTAssertNotNil(s.session("claude:s29"))
    }

    func testLeadPrefersSessionsThatNeedYou() {
        let s = store([event(.userPromptSubmit, "a", at: 0), event(.permissionRequest, "b", at: 1), event(.userPromptSubmit, "c", at: 2)])
        XCTAssertEqual(s.lead?.sessionID, "b")
    }

    func testStaleAndRemovalPolicyNeverInfersFinished() {
        var s = store([event(.userPromptSubmit, "work", at: 0), event(.sessionStart, "quiet", at: 0)])
        let start = Date(timeIntervalSince1970: t0)
        XCTAssertEqual(s.nextDeadline(), start.addingTimeInterval(AgentActivityStore.quietRemoval))
        XCTAssertFalse(s.expire(now: start.addingTimeInterval(60)))
        XCTAssertTrue(s.expire(now: start.addingTimeInterval(AgentActivityStore.quietRemoval)))
        XCTAssertNil(s.session("claude:quiet"))
        XCTAssertEqual(s.session("claude:work")?.status, .working)
        s.expire(now: start.addingTimeInterval(AgentActivityStore.staleAfter))
        XCTAssertEqual(s.session("claude:work")?.status, .stale)
        s.expire(now: start.addingTimeInterval(AgentActivityStore.staleRemoval))
        XCTAssertTrue(s.sessions.isEmpty)
        XCTAssertNil(s.nextDeadline())
    }

    func testSessionEndRemoves() {
        let s = store([event(.sessionStart, at: 0), event(.sessionEnd, at: 1)])
        XCTAssertTrue(s.sessions.isEmpty)
    }
}

final class AgentProjectResolverTests: XCTestCase {
    func testReadsBranchFromHeadAndWorktreePointer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dogbar-repo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("garden")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src/deep"), withIntermediateDirectories: true)
        try "ref: refs/heads/feature/frost\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        let resolved = AgentProjectResolver.resolve(repo.appendingPathComponent("src/deep").path)
        XCTAssertEqual(resolved.project, "garden")
        XCTAssertEqual(resolved.branch, "feature/frost")

        let worktree = root.appendingPathComponent("garden-wt")
        let gitdir = root.appendingPathComponent("gitdirs/wt")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitdir, withIntermediateDirectories: true)
        try "gitdir: \(gitdir.path)\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "0123456789abcdef0123456789abcdef01234567\n".write(to: gitdir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AgentProjectResolver.resolve(worktree.path).branch, "0123456")
    }

    func testBranchParsing() {
        XCTAssertNil(AgentProjectResolver.branch(fromHead: nil))
        XCTAssertNil(AgentProjectResolver.branch(fromHead: "garbage"))
        XCTAssertEqual(AgentProjectResolver.branch(fromHead: "ref: refs/heads/main"), "main")
    }
}

final class AgentHookSetupTests: XCTestCase {
    private let executable = "/Users/o'neil/Applications/DogBar.app/Contents/MacOS/DogBar"

    func testCommandQuotesPathAndIsANoOpWhenMissing() {
        let command = AgentHookSetup.command(executable: executable, client: .claude)
        XCTAssertEqual(command, #"test -x '/Users/o'\''neil/Applications/DogBar.app/Contents/MacOS/DogBar' && exec '/Users/o'\''neil/Applications/DogBar.app/Contents/MacOS/DogBar' --agent-hook claude || true"#)
        let missing = Process()
        missing.executableURL = URL(fileURLWithPath: "/bin/sh")
        missing.arguments = ["-c", AgentHookSetup.command(executable: "/nonexistent/DogBar", client: .codex)]
        missing.standardOutput = Pipe()
        XCTAssertNoThrow(try missing.run())
        missing.waitUntilExit()
        XCTAssertEqual(missing.terminationStatus, 0)
    }

    func testClaudeSettingsShape() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(AgentHookSetup.claudeSettingsJSON(executable: executable).utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(AgentHookSetup.claudeEvents))
        for (event, value) in hooks {
            let group = try XCTUnwrap((value as? [[String: Any]])?.first)
            let handler = try XCTUnwrap((group["hooks"] as? [[String: Any]])?.first)
            XCTAssertEqual(handler["type"] as? String, "command")
            XCTAssertTrue((handler["command"] as? String)?.contains("--agent-hook claude") == true)
            if event == "SessionEnd" { XCTAssertNil(handler["async"]); XCTAssertEqual(handler["timeout"] as? Int, 2) }
            else if event == "Stop" {
                XCTAssertEqual(handler["asyncRewake"] as? Bool, true, "replies wake the session from the background")
                XCTAssertNil(handler["async"])
                XCTAssertEqual(handler["timeout"] as? Int, AgentReplyChannel.hookTimeout)
                XCTAssertTrue((handler["command"] as? String)?.hasSuffix("--agent-hook claude --reply || true") == true)
            } else { XCTAssertEqual(handler["async"] as? Bool, true) }
        }
    }

    func testCodexHooksShape() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(AgentHookSetup.codexHooksJSON(executable: executable).utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(AgentHookSetup.codexEvents))
        let interrupt = try XCTUnwrap(((hooks["Interrupt"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertLessThanOrEqual(try XCTUnwrap(interrupt["timeout"] as? Int), 3, "Codex caps SessionEnd and Interrupt at 3 s")
        XCTAssertTrue((interrupt["command"] as? String)?.contains("--agent-hook codex") == true)
    }

    func testPresenceDetectionIsReadOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dogbar-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        try AgentHookSetup.claudeSettingsJSON(executable: executable).write(to: file, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: file)
        XCTAssertEqual(AgentHookSetup.presence(of: .claude, in: [file]), .found(path: file.path))
        XCTAssertEqual(AgentHookSetup.presence(of: .codex, in: [file]), .notFound)
        XCTAssertEqual(AgentHookSetup.presence(of: .codex, in: [directory.appendingPathComponent("missing.json")]), .notFound)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
}

@MainActor final class AgentEventSocketTests: XCTestCase {
    private func socketURL() -> URL {
        // Short path: sun_path is limited to 104 bytes.
        URL(fileURLWithPath: "/tmp/dogbar-test-\(UUID().uuidString.prefix(8))/events.sock")
    }

    func testEndToEndDeliveryAndRejection() async throws {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = AgentEventListener(url: url)
        var received: [AgentEvent] = []
        listener.onEvent = { received.append($0) }
        try listener.start()
        defer { listener.stop() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        let event = AgentEvent(client: .codex, event: .userPromptSubmit, sid: "live", ts: Date().timeIntervalSince1970)
        XCTAssertTrue(AgentEventSocket.send(try XCTUnwrap(event.encoded()), to: url))
        XCTAssertTrue(AgentEventSocket.send(Data("{garbage".utf8), to: url))
        XCTAssertFalse(AgentEventSocket.send(Data(repeating: 1, count: AgentEvent.maximumWireSize + 1), to: url), "sender refuses oversize")
        for _ in 0..<50 where received.isEmpty || listener.counters.rejected == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(received.map(\.sid), ["live"])
        XCTAssertEqual(listener.counters.accepted, 1)
        XCTAssertEqual(listener.counters.rejected, 1)
    }

    func testSecondListenerReportsInUseAndStaleSocketIsReplaced() throws {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = AgentEventListener(url: url)
        try first.start()
        let second = AgentEventListener(url: url)
        XCTAssertThrowsError(try second.start()) { XCTAssertEqual($0 as? AgentEventListener.Failure, .inUse) }
        first.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        // A leftover file from a crash is not live and gets replaced.
        FileManager.default.createFile(atPath: url.path, contents: Data())
        XCTAssertNoThrow(try second.start())
        second.stop()
    }

    func testSendWithoutListenerFailsQuietly() {
        XCTAssertFalse(AgentEventSocket.send(Data("{}".utf8), to: socketURL()))
    }

    func testPathLimit() {
        let long = URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 120) + "/e.sock")
        XCTAssertThrowsError(try AgentEventListener(url: long).start()) { XCTAssertEqual($0 as? AgentEventListener.Failure, .pathTooLong) }
    }
}

@MainActor final class AgentActivityCenterTests: XCTestCase {
    private func center() -> (AgentActivityCenter, URL) {
        let url = URL(fileURLWithPath: "/tmp/dogbar-center-\(UUID().uuidString.prefix(8))/events.sock")
        return (AgentActivityCenter(listener: AgentEventListener(url: url)), url)
    }

    func testDisabledByDefaultAndDisablingForgetsLiveSessions() throws {
        let (center, url) = center()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(center.connection, .off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "nothing listens until enabled")
        center.setEnabled(true)
        XCTAssertEqual(center.connection, .listening)
        center.receive(AgentEvent(client: .claude, event: .permissionRequest, sid: "s", ts: Date().timeIntervalSince1970, tool: "Bash"))
        XCTAssertEqual(center.displayed.sessions.count, 1, "status changes publish immediately")
        center.setEnabled(false)
        XCTAssertEqual(center.connection, .off)
        XCTAssertTrue(center.displayed.sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDemoIsSeparateFromLiveState() async throws {
        let (center, url) = center()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        center.setEnabled(true)
        defer { center.setEnabled(false) }
        center.receive(AgentEvent(client: .claude, event: .userPromptSubmit, sid: "real", ts: Date().timeIntervalSince1970))
        center.startDemo()
        XCTAssertEqual(center.source, .demo)
        XCTAssertTrue(center.displayed.sessions.isEmpty, "demo starts empty; live sessions are not shown in it")
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertTrue(center.displayed.sessions.allSatisfy { $0.sessionID.hasPrefix("demo-") })
        // A live event during the demo does not leak into the demo display.
        center.receive(AgentEvent(client: .codex, event: .userPromptSubmit, sid: "real2", ts: Date().timeIntervalSince1970))
        XCTAssertNil(center.displayed.sessions.first { !$0.sessionID.hasPrefix("demo-") })
        center.stopDemo()
        XCTAssertEqual(center.source, .live)
        XCTAssertEqual(Set(center.displayed.sessions.map(\.sessionID)), ["real", "real2"])
    }

    func testSelectionBySlotAndAdjacency() {
        let (center, _) = center()
        let now = Date().timeIntervalSince1970
        for sid in ["a", "b", "c"] { center.receive(AgentEvent(client: .claude, event: .sessionStart, sid: sid, ts: now)) }
        center.prepareSelection()
        center.select(slot: 2)
        XCTAssertEqual(center.selectedID, "claude:b")
        center.selectAdjacent(1)
        XCTAssertEqual(center.selectedID, "claude:c")
        center.selectAdjacent(1)
        XCTAssertTrue(center.showingList, "after the last session the arrows reach the list of all sessions")
        center.selectAdjacent(1)
        XCTAssertFalse(center.showingList)
        XCTAssertEqual(center.selectedID, "claude:a")
        center.selectAdjacent(-1)
        XCTAssertTrue(center.showingList)
        center.select(slot: 1)
        center.select(slot: 9)
        XCTAssertEqual(center.selectedID, "claude:a", "an empty slot changes nothing")
        center.receive(AgentEvent(client: .claude, event: .sessionEnd, sid: "a", ts: now + 1))
        XCTAssertEqual(center.selectedID, "claude:b", "removal selects a neighbour, not a reordered list")
    }

    func testDemoScriptIsOrderedAndLabeled() {
        XCTAssertEqual(AgentActivityDemo.script.map(\.at), AgentActivityDemo.script.map(\.at).sorted())
        XCTAssertTrue(AgentActivityDemo.script.allSatisfy { $0.event.sid.hasPrefix("demo-") })
    }
}

final class AgentIslandGeometryTests: XCTestCase {
    func testNotchedDisplayKeepsDogAndRingOutsideTheHousing() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = AgentIslandGeometry(screenFrame: screen, safeAreaTop: 32,
                                           leftAuxiliary: CGRect(x: 0, y: 950, width: 661, height: 32),
                                           rightAuxiliary: CGRect(x: 851, y: 950, width: 661, height: 32), menuBarHeight: 32)
        XCTAssertTrue(geometry.hasNotch)
        XCTAssertEqual(geometry.notchWidth, 190)
        XCTAssertEqual(geometry.centerX, 756)
        XCTAssertEqual(geometry.collapsedSize, CGSize(width: 190 + AgentIslandGeometry.wing * 2, height: 32))
        let collapsed = geometry.shapeFrame(size: geometry.collapsedSize)
        XCTAssertEqual(collapsed.maxY, screen.maxY, "flush with the top edge")
        XCTAssertLessThan(collapsed.minX, 661 - 30, "left wing extends past the housing")
        XCTAssertEqual(geometry.expandedWidth, AgentIslandGeometry.preferredExpandedWidth)
        XCTAssertEqual(geometry.panelFrame.maxY, screen.maxY)
        XCTAssertTrue(geometry.panelFrame.contains(geometry.shapeFrame(size: CGSize(width: geometry.expandedWidth, height: geometry.maximumExpandedHeight))))
    }

    func testDisplayWithoutNotchAndNarrowScreens() {
        let screen = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let geometry = AgentIslandGeometry(screenFrame: screen, safeAreaTop: 0, leftAuxiliary: nil, rightAuxiliary: nil, menuBarHeight: 24)
        XCTAssertFalse(geometry.hasNotch)
        XCTAssertEqual(geometry.centerX, screen.midX)
        XCTAssertEqual(geometry.collapsedSize.height, 24)
        XCTAssertEqual(geometry.panelFrame.maxY, screen.maxY)
        let narrow = AgentIslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 360, height: 600), safeAreaTop: 0, leftAuxiliary: nil, rightAuxiliary: nil, menuBarHeight: 24)
        XCTAssertLessThanOrEqual(narrow.expandedWidth, 360 - 32)
        XCTAssertGreaterThanOrEqual(narrow.panelFrame.minX, 0)
    }
}

final class AgentShortcutPolicyTests: XCTestCase {
    func testCommandDigitsOnlyWhileArmed() {
        var policy = AgentShortcutPolicy()
        XCTAssertEqual(policy.process(keyCode: 18, keyDown: true, command: true, otherModifiers: false, armed: false), .init())
        XCTAssertEqual(policy.process(keyCode: 19, keyDown: true, command: true, otherModifiers: false, armed: true),
                       .init(swallow: true, action: .select(slot: 2)))
        // Its key-up is taken even if the pointer has left by then.
        XCTAssertEqual(policy.process(keyCode: 19, keyDown: false, command: true, otherModifiers: false, armed: false), .init(swallow: true))
        XCTAssertEqual(policy.process(keyCode: 19, keyDown: false, command: true, otherModifiers: false, armed: true), .init())
    }

    func testOtherCombinationsPassThrough() {
        var policy = AgentShortcutPolicy()
        XCTAssertEqual(policy.process(keyCode: 18, keyDown: true, command: true, otherModifiers: true, armed: true), .init())
        XCTAssertEqual(policy.process(keyCode: 18, keyDown: true, command: false, otherModifiers: false, armed: true), .init())
        XCTAssertEqual(policy.process(keyCode: 29, keyDown: true, command: true, otherModifiers: false, armed: true), .init(), "Cmd+0 is not taken")
        XCTAssertEqual(policy.process(keyCode: 53, keyDown: true, command: false, otherModifiers: false, armed: true),
                       .init(swallow: false, action: .collapse), "Escape still reaches the app")
    }
}

final class AgentActivitySettingsTests: XCTestCase {
    @MainActor func testOffByDefaultAlwaysVisibleByDefaultAndReset() throws {
        let suite = "dogbar.tests.agent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.agentActivityEnabled)
        XCTAssertTrue(settings.agentActivityAlwaysVisible)
        settings.agentActivityEnabled = true
        settings.agentActivityAlwaysVisible = false
        settings.reset()
        XCTAssertFalse(settings.agentActivityEnabled)
        XCTAssertTrue(settings.agentActivityAlwaysVisible)
    }

    func testBetaPaneIsSearchable() {
        XCTAssertEqual(SettingsPane.beta.group, .advanced)
        XCTAssertTrue(SettingsSearchIndex.results(for: "codex hooks").contains { $0.anchor == "beta.codex" })
        XCTAssertTrue(SettingsSearchIndex.results(for: "agent activity").contains { $0.anchor == "beta.agentActivity" })
    }
}

final class AgentDogMotionTests: XCTestCase {
    func testReactionsAreFiniteSmallAndEndAtRest() {
        for kind in [AgentDogReaction.Kind.expand, .attention, .finish, .none] {
            let timeline = AgentDogView.timeline(kind)
            XCTAssertLessThanOrEqual(timeline.duration, 0.6, "\(kind) settles quickly")
            let end = timeline.value(time: timeline.duration)
            XCTAssertEqual(end.squashX, 1, accuracy: 0.01)
            XCTAssertEqual(end.squashY, 1, accuracy: 0.01)
            XCTAssertEqual(end.ear, 0, accuracy: 0.2)
            XCTAssertEqual(end.lift, 0, accuracy: 0.05)
            let peaks = AgentDogView.Peaks.of(kind)
            XCTAssertLessThanOrEqual(abs(peaks.squashX - 1), 0.04)
            XCTAssertLessThanOrEqual(abs(peaks.tilt), 2)
            XCTAssertLessThanOrEqual(abs(peaks.ear), 5)
        }
    }

    func testFormatting() {
        let now = Date()
        XCTAssertEqual(IslandFormat.relative(now, now: now), "just now")
        XCTAssertEqual(IslandFormat.relative(now.addingTimeInterval(10), now: now), "just now", "future clock skew never looks newer")
        XCTAssertEqual(IslandFormat.relative(now.addingTimeInterval(-52), now: now), "52s ago")
        XCTAssertEqual(IslandFormat.relative(now.addingTimeInterval(-125), now: now), "2m ago")
        XCTAssertEqual(IslandFormat.duration(125), "2m 05s")
        XCTAssertEqual(IslandFormat.toolName("mcp__memory__create_entities"), "memory · create_entities")
    }
}

final class AgentHookInstallerTests: XCTestCase {
    private var home: URL!
    private let executable = "/Applications/DogBar.app/Contents/MacOS/DogBar"
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("dogbar-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testInstallMergesKeepsOtherSettingsAndIsIdempotent() throws {
        let url = AgentHookInstaller.configURL(for: .claude, home: home)
        let existing = #"{"model":"opus","permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}],"PreCompact":[{"hooks":[{"type":"command","command":"echo x"}]}]}}"#
        try existing.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(AgentHookInstaller.state(of: .claude, executable: executable, home: home), .notInstalled)

        let backup = try AgentHookInstaller.install(.claude, executable: executable, home: home)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(backup), encoding: .utf8), existing, "the previous file is kept")
        try AgentHookInstaller.install(.claude, executable: executable, home: home)
        let object = try json(url)
        XCTAssertEqual(object["model"] as? String, "opus")
        XCTAssertNotNil(object["permissions"])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["Stop"] as? [Any])?.count, 2, "user's Stop hook plus exactly one DogBar group")
        XCTAssertNotNil(hooks["PreCompact"])
        XCTAssertEqual(Set(hooks.keys), Set(AgentHookSetup.claudeEvents).union(["PreCompact"]))
        XCTAssertEqual(AgentHookInstaller.state(of: .claude, executable: executable, home: home), .installed)
        XCTAssertEqual(AgentHookInstaller.state(of: .claude, executable: "/elsewhere/DogBar", home: home), .outdated)

        try AgentHookInstaller.remove(.claude, home: home)
        let cleaned = try json(url)
        let left = try XCTUnwrap(cleaned["hooks"] as? [String: Any])
        XCTAssertEqual(Set(left.keys), ["Stop", "PreCompact"])
        XCTAssertEqual(((left["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String, "say done")
        XCTAssertEqual(cleaned["model"] as? String, "opus")
        XCTAssertEqual(AgentHookInstaller.state(of: .claude, executable: executable, home: home), .notInstalled)
        XCTAssertNil(try AgentHookInstaller.remove(.claude, home: home), "nothing to remove writes nothing")
    }

    func testRemovesOnlyDogBarHandlerInsideSharedGroup() throws {
        let url = AgentHookInstaller.configURL(for: .codex, home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ours = AgentHookSetup.command(executable: executable, client: .codex)
        let shared: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "notify"], ["type": "command", "command": ours]]]]]]
        try JSONSerialization.data(withJSONObject: shared).write(to: url)
        try AgentHookInstaller.remove(.codex, home: home)
        let handlers = try XCTUnwrap(((json(url)["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers.compactMap { $0["command"] as? String }, ["notify"])
    }

    func testCreatesMissingFileAndRemovalLeavesNoEmptyHooks() throws {
        try AgentHookInstaller.install(.codex, executable: executable, home: home)
        let url = AgentHookInstaller.configURL(for: .codex, home: home)
        XCTAssertEqual(Set((try json(url)["hooks"] as? [String: Any])?.keys ?? [:].keys), Set(AgentHookSetup.codexEvents))
        try AgentHookInstaller.remove(.codex, home: home)
        XCTAssertTrue(try json(url).isEmpty)
    }

    func testRefusesInvalidJSONWithoutChangingIt() throws {
        let url = AgentHookInstaller.configURL(for: .claude, home: home)
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AgentHookInstaller.install(.claude, executable: executable, home: home)) {
            guard case .notJSONObject? = $0 as? AgentHookInstaller.Failure else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ not json")
        XCTAssertEqual(AgentHookInstaller.state(of: .claude, executable: executable, home: home), .unreadable)
    }

    func testFollowsSymlinkedSettings() throws {
        let real = home.appendingPathComponent("dotfiles/claude-settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: real, atomically: true, encoding: .utf8)
        let link = AgentHookInstaller.configURL(for: .claude, home: home)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try AgentHookInstaller.install(.claude, executable: executable, home: home)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), real.path, "the link stays a link")
        XCTAssertNotNil(try json(real)["hooks"])
    }
}


final class AgentReplyTests: XCTestCase {
    private let t0 = 1_790_000_000.0

    func testReplyPathValidation() {
        XCTAssertTrue(AgentReplyChannel.isValidReplyPath("/tmp/x/r-0123456789ab.sock"))
        XCTAssertFalse(AgentReplyChannel.isValidReplyPath("relative/r-0123456789ab.sock"))
        XCTAssertFalse(AgentReplyChannel.isValidReplyPath("/tmp/x/events.sock"))
        XCTAssertFalse(AgentReplyChannel.isValidReplyPath("/tmp/x/r-0123456789AB.sock"))
        XCTAssertFalse(AgentReplyChannel.isValidReplyPath("/tmp/../etc/r-0123456789ab.sock"))
    }

    func testStoreKeepsReplyOnlyForTheFinishedTurn() {
        var store = AgentActivityStore()
        func event(_ kind: AgentEvent.Kind, _ at: Double, reply: String? = nil) -> AgentEvent {
            var event = AgentEvent(client: .claude, event: kind, sid: "s", ts: t0 + at)
            event.replyTo = reply
            return event
        }
        store.apply(event(.userPromptSubmit, 0))
        store.apply(event(.stop, 1, reply: "/tmp/r-0123456789ab.sock"))
        XCTAssertTrue(store.sessions[0].canReply)
        store.apply(event(.stop, 0.5, reply: "/tmp/r-aaaaaaaaaaaa.sock"))
        XCTAssertEqual(store.sessions[0].replyPath, "/tmp/r-0123456789ab.sock", "a late Stop does not replace the waiting relay")
        store.apply(event(.userPromptSubmit, 2))
        XCTAssertNil(store.sessions[0].replyPath, "typing in the terminal ends the island reply")
        XCTAssertFalse(store.sessions[0].canReply)
    }

    func testRelayWaiterReceivesReplyAndCancel() throws {
        let directory = URL(fileURLWithPath: "/tmp/dbr-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let waiter = try XCTUnwrap(AgentReplyChannel.Waiter(directory: directory))
        XCTAssertTrue(AgentReplyChannel.isValidReplyPath(waiter.url.path))
        XCTAssertTrue(AgentReplyChannel.send(.init(action: .reply, text: "  yes, ship it \u{7}"), to: waiter.url.path))
        XCTAssertEqual(waiter.wait(timeout: 2), .init(action: .reply, text: "yes, ship it"))
        XCTAssertTrue(AgentReplyChannel.send(.init(action: .cancel), to: waiter.url.path))
        XCTAssertEqual(waiter.wait(timeout: 2)?.action, .cancel)
        XCTAssertNil(waiter.wait(timeout: 0.3), "times out quietly")
        XCTAssertFalse(AgentReplyChannel.send(.init(action: .reply, text: String(repeating: "é", count: 5000)), to: waiter.url.path), "oversize is refused, not truncated")
        let path = waiter.url.path
        _ = consume waiter
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "the relay removes its socket")
        XCTAssertFalse(AgentReplyChannel.send(.init(action: .cancel), to: path))
    }

    func testWakeTextIsLabeled() {
        XCTAssertTrue(AgentReplyChannel.wakeText("hi").contains("DogBar"))
        XCTAssertTrue(AgentReplyChannel.wakeText("hi").hasSuffix("hi"))
    }

    @MainActor func testCenterSendsReplyAndCancelsOnTerminalPrompt() throws {
        let directory = URL(fileURLWithPath: "/tmp/dbc-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let center = AgentActivityCenter(listener: AgentEventListener(url: directory.appendingPathComponent("events.sock")))
        let first = try XCTUnwrap(AgentReplyChannel.Waiter(directory: directory))
        var stop = AgentEvent(client: .claude, event: .stop, sid: "s", ts: Date().timeIntervalSince1970)
        stop.replyTo = first.url.path
        center.receive(AgentEvent(client: .claude, event: .userPromptSubmit, sid: "s", ts: stop.ts - 1))
        center.receive(stop)
        XCTAssertTrue(center.displayed.session("claude:s")?.canReply == true)
        // A prompt typed in the terminal releases the waiting relay.
        center.receive(AgentEvent(client: .claude, event: .userPromptSubmit, sid: "s", ts: stop.ts + 1))
        XCTAssertEqual(first.wait(timeout: 2)?.action, .cancel)

        let second = try XCTUnwrap(AgentReplyChannel.Waiter(directory: directory))
        var next = AgentEvent(client: .claude, event: .stop, sid: "s", ts: stop.ts + 2)
        next.replyTo = second.url.path
        center.receive(next)
        center.drafts["claude:s"] = "go ahead"
        XCTAssertTrue(center.sendReply(to: "claude:s", text: "go ahead"))
        XCTAssertEqual(second.wait(timeout: 2), .init(action: .reply, text: "go ahead"))
        XCTAssertNil(center.drafts["claude:s"])
        XCTAssertFalse(center.displayed.session("claude:s")?.canReply == true)
        XCTAssertFalse(center.sendReply(to: "claude:s", text: "again"), "one reply per turn")
    }

    @MainActor func testReplySocketsOutsideDogBarsFolderAreIgnored() {
        let center = AgentActivityCenter(listener: AgentEventListener(url: URL(fileURLWithPath: "/tmp/dbx-a/events.sock")))
        var stop = AgentEvent(client: .claude, event: .stop, sid: "s", ts: Date().timeIntervalSince1970)
        stop.replyTo = "/tmp/elsewhere/r-0123456789ab.sock"
        center.receive(stop)
        XCTAssertNil(center.displayed.session("claude:s")?.replyPath)
    }

    func testInstallerTracksReplyMode() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("dogbar-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let executable = "/Applications/DogBar.app/Contents/MacOS/DogBar"
        try AgentHookInstaller.install(.claude, executable: executable, home: home, replies: true)
        XCTAssertEqual(AgentHookInstaller.state(of: .claude, executable: executable, home: home, replies: true), .installed)
        XCTAssertEqual(AgentHookInstaller.state(of: .claude, executable: executable, home: home, replies: false), .outdated)
        try AgentHookInstaller.install(.claude, executable: executable, home: home, replies: false)
        XCTAssertEqual(AgentHookInstaller.state(of: .claude, executable: executable, home: home, replies: false), .installed)
    }
}

@MainActor final class AgentSoundAndHostTests: XCTestCase {
    func testCuesAreShortValidWAVs() {
        for cue in AgentSounds.Cue.allCases {
            let data = AgentSounds.wav(for: cue)
            XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
            let seconds = Double(data.count - 44) / (44_100 * 2)
            XCTAssertLessThan(seconds, 1.5, "\(cue) is a short cue")
            XCTAssertNotNil(NSSound(data: data))
        }
    }

    func testParentProcessLookup() {
        XCTAssertEqual(AgentHostApp.parentPID(of: getpid()), getppid())
        XCTAssertNil(AgentHostApp.parentPID(of: 999_999))
    }
}

final class AgentPromptTextTests: XCTestCase {
    func testIslandReplyIsUnwrapped() {
        let raw = "<task-notification>\n<summary>Stop hook feedback</summary>\n</task-notification>\n<system-reminder>\nStop hook blocking error from command \"Stop\": " + AgentReplyChannel.wakeText("say vmro") + "\n</system-reminder>"
        XCTAssertEqual(AgentPromptText.display(raw), .init(text: "say vmro", viaDogBar: true))
    }
    func testInternalTurnsAreNotPrompts() {
        XCTAssertNil(AgentPromptText.display("<task-notification><summary>Background task done</summary></task-notification>"))
        XCTAssertNil(AgentPromptText.display("<system-reminder>x</system-reminder>"))
        XCTAssertNil(AgentPromptText.display("   "))
    }
    func testSlashCommandsAndPlainText() {
        XCTAssertEqual(AgentPromptText.display("<command-message>review</command-message>\n<command-name>/review</command-name>\n<command-args>main</command-args>")?.text, "/review main")
        XCTAssertEqual(AgentPromptText.display("<command-name>clear</command-name>")?.text, "/clear")
        XCTAssertEqual(AgentPromptText.display("make a <div> centered"), .init(text: "make a <div> centered", viaDogBar: false))
    }
    func testRelayAndStoreUseCleanPrompt() throws {
        let raw = "<system-reminder>\nStop hook blocking error: " + AgentReplyChannel.wakeText("ship it") + "\n</system-reminder>"
        let json = try JSONSerialization.data(withJSONObject: ["session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": raw])
        let event = try XCTUnwrap(AgentHookRelay.event(fromHookJSON: json, client: .claude, now: Date(timeIntervalSince1970: 1_790_000_000)))
        XCTAssertEqual(event.prompt, "ship it")
        XCTAssertEqual(event.promptViaDogBar, true)
        var store = AgentActivityStore()
        store.apply(event)
        XCTAssertEqual(store.sessions.first?.lastPrompt, "ship it")
        XCTAssertEqual(store.sessions.first?.lastPromptViaDogBar, true)
        // An internal turn keeps the previous prompt instead of showing markup.
        let internalTurn = try JSONSerialization.data(withJSONObject: ["session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "<task-notification>x</task-notification>"])
        store.apply(try XCTUnwrap(AgentHookRelay.event(fromHookJSON: internalTurn, client: .claude, now: Date(timeIntervalSince1970: 1_790_000_010))))
        XCTAssertEqual(store.sessions.first?.lastPrompt, "ship it")
    }
    func testMarkdownRendersInlineAndTidiesBlocks() {
        let text = String(IslandFormat.markdown("## Done\n- **Update** the `hooks`\nplain").characters)
        XCTAssertEqual(text, "Done\n• Update the hooks\nplain")
    }
}

@MainActor final class AgentAttentionAndDismissTests: XCTestCase {
    private func center() -> AgentActivityCenter {
        AgentActivityCenter(listener: AgentEventListener(url: URL(fileURLWithPath: "/tmp/dbd-\(UUID().uuidString.prefix(6))/events.sock")))
    }
    func testAttentionBadges() throws {
        let center = center()
        let now = Date().timeIntervalSince1970
        center.receive(AgentEvent(client: .claude, event: .permissionRequest, sid: "a", ts: now))
        center.receive(AgentEvent(client: .claude, event: .stop, sid: "b", ts: now))
        center.receive(AgentEvent(client: .claude, event: .stopFailure, sid: "c", ts: now, error: "rate_limit"))
        center.receive(AgentEvent(client: .claude, event: .userPromptSubmit, sid: "d", ts: now))
        let store = center.displayed
        XCTAssertEqual(center.attention(for: try XCTUnwrap(store.session("claude:a"))), .needsYou)
        XCTAssertEqual(center.attention(for: try XCTUnwrap(store.session("claude:b"))), .unseen)
        XCTAssertEqual(center.attention(for: try XCTUnwrap(store.session("claude:c"))), .failed)
        XCTAssertNil(center.attention(for: try XCTUnwrap(store.session("claude:d"))))
        center.markSeen("claude:b")
        XCTAssertNil(center.attention(for: try XCTUnwrap(center.displayed.session("claude:b"))), "looking clears the badge")
        center.markSeen("claude:a")
        XCTAssertEqual(center.attention(for: try XCTUnwrap(center.displayed.session("claude:a"))), .needsYou, "needs you stays until answered")
    }
    func testDismissHidesUntilNewTurnOrNeedsYou() {
        let center = center()
        let now = Date().timeIntervalSince1970
        center.receive(AgentEvent(client: .claude, event: .userPromptSubmit, sid: "a", ts: now))
        center.receive(AgentEvent(client: .claude, event: .sessionStart, sid: "b", ts: now))
        center.dismiss("claude:a")
        XCTAssertNil(center.displayed.session("claude:a"))
        center.receive(AgentEvent(client: .claude, event: .postToolUse, sid: "a", ts: now + 1, tool: "Read", toolUseID: "1"))
        XCTAssertNil(center.displayed.session("claude:a"), "ordinary activity keeps it hidden")
        center.receive(AgentEvent(client: .claude, event: .permissionRequest, sid: "a", ts: now + 2, tool: "Bash"))
        XCTAssertEqual(center.displayed.session("claude:a")?.status, .needsYou, "it comes back when it needs you")
        center.dismiss("claude:b")
        center.receive(AgentEvent(client: .claude, event: .userPromptSubmit, sid: "b", ts: now + 3))
        XCTAssertNotNil(center.displayed.session("claude:b"), "and on a new turn")
    }
}

final class AgentMessageSizeTests: XCTestCase {
    func testLongNonASCIIReplyStillFitsOneEvent() throws {
        var event = AgentEvent(client: .claude, event: .stop, sid: "s", ts: 1_790_000_000, cwd: String(repeating: "/ä", count: 400))
        event.message = String(repeating: "é漢", count: 3000)
        event.prompt = String(repeating: "ü", count: 1000)
        let clean = try event.validated()
        XCTAssertLessThanOrEqual(clean.message?.utf8.count ?? 0, AgentEvent.Limit.messageBytes)
        XCTAssertNotNil(clean.encoded(), "a long reply never makes the event too big to send")
    }
}
