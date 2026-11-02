import AppKit
import Darwin

/// A GUI application process that exists but has not checked in with LaunchServices yet.
public struct LaunchCandidate: Equatable, Sendable {
    public let pid: pid_t
    public let bundleIdentifier: String?
    public let name: String
    public let bundleURL: URL
}

/// Pure eligibility for spawned processes. Only a top-level `.app` bundle's own executable,
/// started by launchd and not declared agent/background-only, can be a Dock application.
internal enum LaunchCandidatePolicy {
    static let launchTrampoline = "/usr/libexec/xpcproxy"
    /// `Foo.app/Contents/MacOS/Foo` -> bundle path and executable name. Helpers nested in
    /// another bundle (Electron renderers, XPC services, login items) are rejected.
    static func bundle(executablePath path: String) -> (bundlePath: String, executable: String)? {
        guard let range = path.range(of: ".app/Contents/MacOS/", options: .backwards) else { return nil }
        let bundlePath = String(path[..<range.lowerBound]) + ".app"
        let executable = String(path[range.upperBound...])
        guard !executable.isEmpty, !executable.contains("/"), !bundlePath.dropLast(4).contains("/Contents/") else { return nil }
        return (bundlePath, executable)
    }
    /// LaunchServices runs apps as launchd jobs labelled `application.<bundle>.<n>.<n>`.
    /// A readable, different label is a LaunchAgent using an app executable. Platform
    /// binaries hide their environment, so an unknown label does not reject a launch.
    static func isLaunchServicesJob(serviceName: String?) -> Bool {
        serviceName.map { $0.hasPrefix("application.") } ?? true
    }
    static func candidate(pid: pid_t, parentPID: pid_t, executablePath: String, serviceName: String? = nil, info: [String: Any]?, excludingBundleIdentifier own: String?) -> LaunchCandidate? {
        // LaunchServices/RunningBoard launches are children of launchd. Terminal-run binaries are not.
        guard parentPID == 1, isLaunchServicesJob(serviceName: serviceName),
              let parts = bundle(executablePath: executablePath), let info else { return nil }
        func flag(_ key: String) -> Bool {
            if let number = info[key] as? NSNumber { return number.boolValue }
            if let string = info[key] as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
            return false
        }
        guard (info["CFBundlePackageType"] as? String ?? "APPL") == "APPL",
              (info["CFBundleExecutable"] as? String ?? parts.executable) == parts.executable,
              !flag("LSUIElement"), !flag("LSBackgroundOnly") else { return nil }
        let identifier = info["CFBundleIdentifier"] as? String
        if let own, identifier == own { return nil }
        let url = URL(fileURLWithPath: parts.bundlePath, isDirectory: true)
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        return LaunchCandidate(pid: pid, bundleIdentifier: identifier, name: name, bundleURL: url)
    }
}

/// LaunchServices announces an app (willLaunch, didActivate, runningApplications KVO) only when
/// the process checks in, after dyld loading and NSApplication start-up. Cold launches spend
/// seconds before that point while the native Dock is already bouncing. This reports the
/// process itself: one PID-table diff per tick on a utility queue (tens of microseconds),
/// per-process detail only for new PIDs, and no Accessibility or LaunchServices calls.
@MainActor public final class LaunchProcessMonitor {
    public var onSpawn: ((LaunchCandidate) -> Void)?
    public var onExit: ((pid_t) -> Void)?
    private var worker: LaunchProcessWorker?
    public init() {}
    deinit { worker?.stop() }
    public func start() {
        guard worker == nil else { return }
        let worker = LaunchProcessWorker()
        self.worker = worker
        worker.start(spawn: { [weak self, weak worker] candidate in
            DispatchQueue.main.async { [weak self, weak worker] in
                guard let self, let worker, self.worker === worker else { return }
                self.onSpawn?(candidate)
            }
        }, exit: { [weak self, weak worker] pid in
            DispatchQueue.main.async { [weak self, weak worker] in
                guard let self, let worker, self.worker === worker else { return }
                self.onExit?(pid)
            }
        })
    }
    public func stop() { worker?.stop(); worker = nil }
    /// LaunchServices owns the process after check-in or retirement; drop its exit source.
    public func forget(pid: pid_t) { worker?.forget(pid: pid) }
}

// All mutable state is confined to queue.
private final class LaunchProcessWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.hristijan.dogbar.launches", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var known = Set<pid_t>()
    private var exits: [pid_t: DispatchSourceProcess] = [:]
    private var buffer = [pid_t](repeating: 0, count: 4096)
    private var startedAt: time_t = 0
    private var spawn: ((LaunchCandidate) -> Void)?
    private var exit: ((pid_t) -> Void)?
    private let ownBundleIdentifier = Bundle.main.bundleIdentifier
    func start(spawn: @escaping (LaunchCandidate) -> Void, exit: @escaping (pid_t) -> Void) {
        queue.async {
            self.spawn = spawn; self.exit = exit
            self.startedAt = time(nil)
            // Seed with everything already running; only later processes are launches.
            self.known = Set(self.pids())
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(40))
            timer.setEventHandler { [weak self] in self?.scan() }
            timer.resume(); self.timer = timer
        }
    }
    func stop() {
        queue.async {
            self.timer?.cancel(); self.timer = nil
            for source in self.exits.values { source.cancel() }
            self.exits.removeAll(); self.known.removeAll()
            self.spawn = nil; self.exit = nil
        }
    }
    func forget(pid: pid_t) { queue.async { self.exits.removeValue(forKey: pid)?.cancel() } }
    private func pids() -> [pid_t] {
        while true {
            let bytes = proc_listpids(UInt32(PROC_UID_ONLY), UInt32(getuid()), &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
            guard bytes > 0 else { return [] }
            let count = Int(bytes) / MemoryLayout<pid_t>.size
            if count < buffer.count { return Array(buffer[0..<count]) }
            buffer = [pid_t](repeating: 0, count: buffer.count * 2)
        }
    }
    private func scan() {
        guard spawn != nil else { return }
        let current = pids()
        guard !current.isEmpty else { return }
        var next = Set<pid_t>(minimumCapacity: current.count)
        for pid in current where known.contains(pid) || inspect(pid) { next.insert(pid) }
        known = next
    }
    /// Returns false while launchd's trampoline has not exec'd the app yet, so the PID is
    /// inspected again next tick instead of being remembered as an unrelated process.
    private func inspect(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == Int32(MemoryLayout<proc_bsdinfo>.size) else { return true }
        guard info.pbi_ppid == 1, time_t(info.pbi_start_tvsec) >= startedAt - 1 else { return true }
        var raw = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &raw, UInt32(raw.count)) > 0 else { return true }
        let path = String(cString: raw)
        if path == LaunchCandidatePolicy.launchTrampoline { return time(nil) - time_t(info.pbi_start_tvsec) > 10 }
        guard let parts = LaunchCandidatePolicy.bundle(executablePath: path) else { return true }
        // Read only for new launchd-started app executables, never cached across app updates.
        let bundleInfo = NSDictionary(contentsOfFile: parts.bundlePath + "/Contents/Info.plist") as? [String: Any]
        guard let candidate = LaunchCandidatePolicy.candidate(pid: pid, parentPID: pid_t(info.pbi_ppid), executablePath: path,
                                                              serviceName: serviceName(pid), info: bundleInfo, excludingBundleIdentifier: ownBundleIdentifier) else { return true }
        watchExit(pid)
        spawn?(candidate)
        return true
    }
    /// `XPC_SERVICE_NAME` from the process environment, when the kernel exposes it.
    private func serviceName(_ pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        let key = "XPC_SERVICE_NAME="
        var index = MemoryLayout<Int32>.size
        while index < size {
            let start = index
            while index < size && bytes[index] != 0 { index += 1 }
            if index > start, let value = String(bytes: bytes[start..<index], encoding: .utf8), value.hasPrefix(key) {
                return String(value.dropFirst(key.count))
            }
            index += 1
        }
        return nil
    }
    private func watchExit(_ pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, self.exits.removeValue(forKey: pid) != nil else { return }
            source.cancel(); self.exit?(pid)
        }
        exits[pid]?.cancel(); exits[pid] = source
        source.resume()
        // A process that exits before registration never fires the source.
        if kill(pid, 0) != 0 && errno == ESRCH, exits.removeValue(forKey: pid) != nil {
            source.cancel(); exit?(pid)
        }
    }
}
