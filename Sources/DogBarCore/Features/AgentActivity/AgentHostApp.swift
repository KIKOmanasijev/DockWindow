import AppKit
import Darwin

/// The app a session runs in (Terminal, Ghostty, iTerm, VS Code, …): the nearest ancestor of the agent
/// process that is a regular app. Activating it is reliable; picking the exact tab is not, so DogBar doesn't try.
public struct AgentHostApp: Equatable {
    public let pid: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let icon: NSImage?
    /// The agent process this was resolved from, so it is only re-resolved when that changes.
    var pidSource: pid_t? = nil
    func withSource(_ pid: pid_t) -> AgentHostApp { var copy = self; copy.pidSource = pid; return copy }

    public static func == (lhs: AgentHostApp, rhs: AgentHostApp) -> Bool { lhs.pid == rhs.pid }

    @MainActor public static func resolve(from pid: pid_t) -> AgentHostApp? {
        var current = pid
        for _ in 0..<32 {
            guard current > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular, !app.isTerminated {
                return AgentHostApp(pid: current, name: app.localizedName ?? "App", bundleIdentifier: app.bundleIdentifier, icon: app.icon)
            }
            guard let parent = parentPID(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// Brings the hosting app forward. Returns false if it has quit.
    @MainActor @discardableResult public func activate() -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        if app.isHidden { app.unhide() }
        return app.activate(options: [.activateAllWindows])
    }
}

/// Small agent identity marks. Uses the agent's own installed app icon when present, else a neutral glyph.
@MainActor enum AgentClientIcon {
    private static var cache: [AgentClient: NSImage?] = [:]
    static func image(_ client: AgentClient) -> NSImage? {
        if let cached = cache[client] { return cached }
        let ids = client == .claude ? ["com.anthropic.claudefordesktop", "com.anthropic.claude"] : ["com.openai.codex", "com.openai.chat"]
        let icon = ids.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[client] = icon
        return icon
    }
    static func symbol(_ client: AgentClient) -> String { client == .claude ? "asterisk" : "chevron.left.forwardslash.chevron.right" }
}
