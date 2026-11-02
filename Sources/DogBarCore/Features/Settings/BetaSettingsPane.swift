import AppKit
import SwiftUI

/// Opt-in experiments. Agent Activity is off until turned on here. DogBar edits Claude Code or
/// Codex configuration only when Install or Remove is pressed, and only its own hook entries.
@MainActor struct BetaSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var center: AgentActivityCenter
    @ObservedObject var visibility: SettingsVisibility
    @State private var hookStates: [AgentClient: AgentHookInstaller.State] = [:]
    @State private var copied: AgentClient?
    @State private var working: AgentClient?
    @State private var notice: (client: AgentClient, text: String, isError: Bool)?
    @State private var previewSounds = AgentSounds()

    private var executable: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }
    private var isInstalledCopy: Bool {
        let path = Bundle.main.bundlePath
        return path.hasSuffix(".app") && (path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/"))
    }

    var body: some View {
        Group {
            SettingsHero(title: "Agent Activity",
                         text: "A small dog for each Claude Code or Codex session at the top of your screen. See which agent is working, needs you, or has finished a turn.") {
                AgentActivityHeroArt()
            } control: {
                Toggle("Agent Activity", isOn: $settings.agentActivityEnabled)
                    .settingsDescription("Beta, off by default. DogBar never approves anything for an agent; it sends text to Claude Code only when you reply from the island.")
                    .settingsAnchor("beta.agentActivity")
            }
            SettingsSection("Island") {
                Toggle("Always show the island", isOn: $settings.agentActivityAlwaysVisible)
                    .settingsDescription("Keep a small resting island at the top of the screen when no session is active. Off: it appears only while a session is reported.")
                    .settingsAnchor("beta.alwaysVisible")
                Toggle("Sounds", isOn: Binding(get: { settings.agentActivitySounds }, set: { value in
                    settings.agentActivitySounds = value
                    if value { previewSounds.play(.finished, force: true) }
                }))
                    .settingsDescription("A soft cue when a session needs you, finishes a turn, or fails. Nothing for individual tool calls.")
                    .settingsAnchor("beta.sounds")
                SettingsRow("Connection", description: connectionDescription) {
                    HStack(spacing: 10) {
                        SettingsStatusPill(text: connectionLabel.text, symbol: connectionLabel.symbol, tone: connectionLabel.tone)
                        if case .failed = center.connection { Button("Try Again") { center.retry() } }
                    }
                }
                .settingsAnchor("beta.connection")
                SettingsRowText(title: Text("Shortcuts"), description: "With the pointer over the open island, ⌘1–⌘9 choose a session and Esc closes it. Other apps keep their shortcuts the rest of the time. Needs Accessibility.")
            }
            SettingsSection("Demo", footer: "The demo is simulated. Its island is marked DEMO, it never mixes with live sessions, and it stops when Settings closes.") {
                SettingsRow("Simulated activity", description: "Three made-up sessions: working with tool calls, asking for permission, finishing a turn and an error. Works with Agent Activity off.") {
                    if center.isDemoRunning {
                        Button("Stop Demo") { center.stopDemo() }
                    } else {
                        Button("Play Demo") { center.startDemo() }
                    }
                }
                .settingsAnchor("beta.demo")
            }
            hookSection(.claude)
            hookSection(.codex)
            SettingsSection("Privacy") {
                SettingsDescriptionText("Hooks forward only the session ID, folder, event name, tool name, the first 300 characters of your prompt, and the agent’s final reply or notification text, through a private socket on this Mac. Tool inputs never leave the hook. Replies you type go only to that session’s waiting hook. Nothing is sent over the network, and live sessions are forgotten when Agent Activity is turned off or DogBar quits.")
                    .padding(.vertical, 2)
            }
        }
        .task(id: visibility.isVisible) { if visibility.isVisible { await refreshStates() } }
        .onChange(of: settings.agentActivityReplies) { _, _ in Task { await refreshStates() } }
    }

    // MARK: Connection

    private var connectionLabel: (text: String, symbol: String?, tone: SettingsStatusPill.Tone) {
        switch center.connection {
        case .off: return ("Off", nil, .neutral)
        case .listening: return center.lastEvent == nil ? ("Listening", "dot.radiowaves.left.and.right", .neutral) : ("Receiving events", "checkmark.circle.fill", .good)
        case .failed: return ("Not listening", "exclamationmark.triangle.fill", .warning)
        }
    }

    private var connectionDescription: String {
        var parts: [String] = []
        switch center.connection {
        case .off: parts.append("Live observation starts when Agent Activity is on.")
        case .listening: parts.append(lastEventText)
        case .failed(let failure): parts.append(failure.message)
        }
        let counters = center.counters
        if counters.rejected > 0 { parts.append("Ignored \(counters.rejected) malformed \(counters.rejected == 1 ? "event" : "events").") }
        if counters.rateLimited > 0 { parts.append("Dropped \(counters.rateLimited) during a burst.") }
        return parts.joined(separator: " ")
    }

    private var lastEventText: String {
        guard let last = center.lastEvent else { return "Waiting for the first hook event. Set up hooks below, then start a new agent session." }
        return "Last event: \(last.client.displayName) \(last.kind.rawValue), \(last.receivedAt.formatted(.relative(presentation: .named)))."
    }

    // MARK: Hooks

    private var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    private func hookSection(_ client: AgentClient) -> some View {
        let isClaude = client == .claude
        let file = (AgentHookInstaller.configURL(for: client, home: home).path as NSString).abbreviatingWithTildeInPath
        let state = hookStates[client]
        let description = isClaude
            ? "Adds DogBar’s hooks to \(file), next to any hooks you already have. They run in the background, so Claude Code never waits for DogBar. Start a new session afterwards."
            : "Adds DogBar’s hooks to \(file), next to any hooks you already have. Then run /hooks in Codex to review and trust them; Codex asks again whenever a hook changes."
        return SettingsSection(client.displayName) {
            SettingsRow("Hooks", description: description) {
                HStack(spacing: 8) {
                    switch state {
                    case .installed?:
                        Button("Remove") { run(client, install: false) }.settingsNeutralControl()
                    case .outdated?:
                        Button("Remove") { run(client, install: false) }.settingsNeutralControl()
                        Button("Update") { run(client, install: true) }.buttonStyle(.borderedProminent)
                    case .unreadable?:
                        EmptyView()
                    case .notInstalled?, nil:
                        Button("Install") { run(client, install: true) }.buttonStyle(.borderedProminent)
                    }
                }
                .disabled(working != nil || state == nil)
            }
            .settingsAnchor(isClaude ? "beta.claude" : "beta.codex")
            HStack(spacing: 8) {
                statusLabel(client)
                Spacer(minLength: 0)
            }
            if let notice, notice.client == client {
                Text(notice.text).font(.system(size: 11.5))
                    .foregroundStyle(notice.isError ? SettingsPalette.caution : SettingsPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isInstalledCopy {
                Label("This copy of DogBar runs from \((Bundle.main.bundlePath as NSString).abbreviatingWithTildeInPath). Hooks point at this exact file, so install them from the copy you keep.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5)).foregroundStyle(SettingsPalette.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isClaude {
                Toggle("Reply from the island", isOn: $settings.agentActivityReplies)
                    .settingsDescription("When a turn finishes, type your answer in the island. Claude Code receives it as a note from DogBar and continues. Uses a background Stop hook (asyncRewake), so Claude Code never waits. Update the hooks after changing this.")
                    .settingsAnchor("beta.replies")
            }
            SettingsMore(isClaude ? "beta.claude.manual" : "beta.codex.manual", title: "Show configuration") {
                manualSetup(client)
            }
        }
    }

    private func manualSetup(_ client: AgentClient) -> some View {
        let snippet = client == .claude ? AgentHookSetup.claudeSettingsJSON(executable: executable, replies: settings.agentActivityReplies) : AgentHookSetup.codexHooksJSON(executable: executable)
        return VStack(alignment: .leading, spacing: 8) {
            SettingsDescriptionText("To set it up by hand, merge this into the file yourself.")
            ScrollView([.vertical, .horizontal]) {
                Text(snippet).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .foregroundStyle(SettingsPalette.text)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .accessibilityLabel("\(client.displayName) hook configuration")
            Button(copied == client ? "Copied" : "Copy Configuration") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(snippet, forType: .string)
                copied = client
            }
            .settingsNeutralControl()
        }
    }

    @ViewBuilder private func statusLabel(_ client: AgentClient) -> some View {
        if let received = center.lastEventByClient[client] {
            SettingsStatusPill(text: "Event received \(received.formatted(.relative(presentation: .named)))", symbol: "checkmark.circle.fill", tone: .good)
        } else {
            switch hookStates[client] {
            case .installed?: SettingsStatusPill(text: center.isEnabled ? "Installed, waiting for a session" : "Installed. Turn on Agent Activity to see sessions", symbol: "clock", tone: .neutral)
            case .outdated?: SettingsStatusPill(text: "Installed for another copy of DogBar", symbol: "exclamationmark.triangle.fill", tone: .warning)
            case .unreadable?: SettingsStatusPill(text: "Couldn’t read the config file", symbol: "exclamationmark.triangle.fill", tone: .warning)
            case .notInstalled?: SettingsStatusPill(text: "Not installed", symbol: nil, tone: .neutral)
            case nil: SettingsStatusPill(text: "Checking…", symbol: nil, tone: .neutral)
            }
        }
    }

    private func run(_ client: AgentClient, install: Bool) {
        working = client
        let home = home, executable = executable, replies = settings.agentActivityReplies
        Task {
            let result: Result<URL?, AgentHookInstaller.Failure> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(install ? try AgentHookInstaller.install(client, executable: executable, home: home, replies: replies)
                                            : try AgentHookInstaller.remove(client, home: home))
                } catch { return .failure(error as? AgentHookInstaller.Failure ?? .unwritable(error.localizedDescription)) }
            }.value
            switch result {
            case .success(let backup):
                let saved = backup.map { " The previous file is saved as \(($0.lastPathComponent))." } ?? ""
                let next = !install ? "Removed DogBar’s hooks." : client == .codex ? "Installed. Run /hooks in Codex to trust them." : "Installed. Start a new Claude Code session."
                notice = (client, next + saved, false)
                if install && !settings.agentActivityEnabled { settings.agentActivityEnabled = true }
            case .failure(let failure):
                notice = (client, failure.errorDescription ?? "Something went wrong.", true)
            }
            working = nil
            await refreshStates()
        }
    }

    /// Reads (never writes) both config files to see whether DogBar's hooks are there.
    private func refreshStates() async {
        let home = home, executable = executable, replies = settings.agentActivityReplies
        let states = await Task.detached(priority: .utility) {
            [AgentClient.claude: AgentHookInstaller.state(of: .claude, executable: executable, home: home, replies: replies),
             .codex: AgentHookInstaller.state(of: .codex, executable: executable, home: home)]
        }.value
        hookStates = states
    }
}

/// A still miniature of the island for the hero: three sessions' dogs on the black shell.
private struct AgentActivityHeroArt: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x24202C))
            IslandShape(bottomRadius: 18, shoulder: 6)
                .fill(IslandPalette.shell)
                .frame(width: 132, height: 48)
                .overlay(alignment: .leading) {
                    HStack(spacing: -4) {
                        AgentDogView(coat: AgentCoat.palette(0), mood: .working, size: 30, reduceMotion: true)
                        AgentDogView(coat: AgentCoat.palette(1), mood: .needsYou, size: 24, reduceMotion: true)
                        AgentDogView(coat: AgentCoat.palette(3), mood: .finished, size: 24, reduceMotion: true)
                    }
                    .padding(.leading, 14).padding(.bottom, 4)
                }
                .overlay(alignment: .trailing) {
                    AgentStatusRing(status: .working, failed: false, demo: false, animate: false, size: 16).padding(.trailing, 16).padding(.bottom, 4)
                }
        }
        .frame(width: 160, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}
