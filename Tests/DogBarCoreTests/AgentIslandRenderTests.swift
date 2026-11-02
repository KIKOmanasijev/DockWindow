import AppKit
import SwiftUI
import XCTest
@testable import DogBarCore

/// Offscreen stills of the island for visual review. Skipped unless DOGBAR_RENDER_DIR is set, e.g.
/// `DOGBAR_RENDER_DIR=/tmp/island swift test --filter AgentIslandRenderTests`. Stills cannot show motion.
@MainActor final class AgentIslandRenderTests: XCTestCase {
    func testRenderStills() async throws {
        guard let path = ProcessInfo.processInfo.environment["DOGBAR_RENDER_DIR"] else { throw XCTSkip("Set DOGBAR_RENDER_DIR to render stills") }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let notch = AgentIslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                        leftAuxiliary: CGRect(x: 0, y: 950, width: 661, height: 32),
                                        rightAuxiliary: CGRect(x: 851, y: 950, width: 661, height: 32), menuBarHeight: 32)
        let center = AgentActivityCenter(listener: AgentEventListener(url: URL(fileURLWithPath: "/tmp/dogbar-render-unused.sock")))
        let now = Date().timeIntervalSince1970
        func send(_ kind: AgentEvent.Kind, _ sid: String, _ at: Double, client: AgentClient = .claude, tool: String? = nil, id: String? = nil,
                  message: String? = nil, model: String? = nil, cwd: String = "/Users/me/DockWindow", title: String? = nil,
                  prompt: String? = nil, replyTo: String? = nil) {
            var event = AgentEvent(client: client, event: kind, sid: sid, ts: now - 90 + at, cwd: cwd, tool: tool, toolUseID: id,
                                   message: message, title: title, model: model)
            event.prompt = prompt; event.replyTo = replyTo; event.hostPID = ProcessInfo.processInfo.environment["DOGBAR_RENDER_HOSTS"] == nil ? nil : getpid()
            center.receive(event)
        }
        send(.sessionStart, "one", 0, title: "DogBar Agent Activity MVP")
        send(.userPromptSubmit, "one", 1)
        send(.stop, "one", 2, message: "Replies need **one action** from you: press **Update** in `Settings › Beta`.")
        send(.userPromptSubmit, "one", 3, prompt: "Give each Settings feature its own page and keep the sidebar grouped")
        for index in 0..<14 { send(.preToolUse, "one", 4 + Double(index), tool: "Bash", id: "b\(index)"); send(index == 5 ? .postToolUseFailure : .postToolUse, "one", 4.5 + Double(index), tool: "Bash", id: "b\(index)") }
        for index in 0..<7 { send(.postToolUse, "one", 20 + Double(index), tool: "Read", id: "r\(index)") }
        send(.postToolUse, "one", 88, tool: "ToolSearch", id: "t1")
        send(.preToolUse, "one", 89, tool: "Edit", id: "e1")
        send(.sessionStart, "two", 5, client: .codex, model: "gpt-5.5-codex", cwd: "/Users/me/weather-api")
        send(.userPromptSubmit, "two", 50, client: .codex, cwd: "/Users/me/weather-api", prompt: "Add a retry policy to the forecast client")
        send(.permissionRequest, "two", 60, client: .codex, tool: "shell", cwd: "/Users/me/weather-api")
        send(.sessionStart, "three", 6, cwd: "/Users/me/handbook")
        send(.userPromptSubmit, "three", 7, cwd: "/Users/me/handbook", prompt: "say hi again")
        send(.stop, "three", 70, message: "All three changes are in, and the new build is installed in `~/Applications` and running.\n\n**1. Attention badges on the dots.** Each dot keeps its session colour and gets a small corner badge: amber when it needs you, red when its last turn failed, green when a turn finished that you haven't looked at yet.\n\n**2. The XML text.** Island replies show as your text with a small reply arrow.\n\n**3. Removing sessions.** Hover a row for a small ×.", cwd: "/Users/me/handbook", replyTo: "/tmp/r-0123456789ab.sock")
        // Flush coalesced updates.
        try? await Task.sleep(for: .milliseconds(200))

        /// Real AppKit rendering in an offscreen window, so text fields and app icons draw as they do on screen.
        func render<V: View>(_ view: V, _ name: String, size: CGSize) {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(hex: 0x6B4A3A)))
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.appearance = NSAppearance(named: .darkAqua)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("render \(name)") }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
        }
        let panel = notch.panelFrame.size
        for (name, sid) in [("expanded-working", "claude:one"), ("expanded-needs-you", "codex:two"), ("expanded-finished", "claude:three")] {
            let model = AgentIslandModel(geometry: notch)
            model.expanded = true; model.reduceMotion = true; model.shortcutsAvailable = true
            model.contentHeight = 470
            center.select(sid)
            render(AgentIslandView(model: model, center: center), name, size: panel)
        }
        let listModel = AgentIslandModel(geometry: notch)
        listModel.expanded = true; listModel.reduceMotion = true; listModel.shortcutsAvailable = true; listModel.contentHeight = 330
        center.showList()
        render(AgentIslandView(model: listModel, center: center), "expanded-list", size: panel)
        let two = AgentIslandModel(geometry: notch)
        two.reduceMotion = true; two.sessionCount = 2
        let pair = AgentActivityCenter(listener: AgentEventListener(url: URL(fileURLWithPath: "/tmp/dogbar-render-unused3.sock")))
        pair.receive(AgentEvent(client: .claude, event: .userPromptSubmit, sid: "p1", ts: now))
        pair.receive(AgentEvent(client: .codex, event: .sessionStart, sid: "p2", ts: now))
        render(AgentIslandView(model: two, center: pair), "collapsed-two", size: CGSize(width: panel.width, height: 60))
        let collapsed = AgentIslandModel(geometry: notch)
        collapsed.reduceMotion = true
        collapsed.sessionCount = 3
        render(AgentIslandView(model: collapsed, center: center), "collapsed", size: CGSize(width: panel.width, height: 60))
        let empty = AgentActivityCenter(listener: AgentEventListener(url: URL(fileURLWithPath: "/tmp/dogbar-render-unused2.sock")))
        collapsed.sessionCount = 0
        render(AgentIslandView(model: collapsed, center: empty), "collapsed-empty", size: CGSize(width: panel.width, height: 60))

        let moods: [AgentMood] = [.idle, .working, .needsYou, .finished, .troubled, .stale]
        let gallery = VStack(spacing: 12) {
            ForEach(0..<AgentActivityStore.coatCount, id: \.self) { coat in
                HStack(spacing: 12) {
                    ForEach(moods.indices, id: \.self) { index in
                        AgentDogView(coat: AgentCoat.palette(coat), mood: moods[index], size: 64, reduceMotion: true)
                    }
                }
            }
        }.padding(16).background(Color.black)
        render(gallery, "dog-gallery", size: CGSize(width: 6 * 76 + 20, height: 8 * 76 + 20))
    }
}
