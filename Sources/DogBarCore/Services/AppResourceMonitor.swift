import AppKit
import Darwin

public struct AppResourceUsage: Sendable {
    public let cpuPercent: Double?
    public let residentBytes: UInt64
}

/// Samples only while a preview is visible. Totals are process-wide, not per-window.
@MainActor final class AppResourceMonitor {
    private var task: Task<Void, Never>?
    private var pid: pid_t?
    func stop() { task?.cancel(); task = nil; pid = nil }
    func start(pid: pid_t, bundleURL: URL?, receive: @escaping (AppResourceUsage?) -> Void) {
        guard self.pid != pid || task == nil else { return }
        stop(); self.pid = pid
        task = Task {
            var previous: Sample?
            while !Task.isCancelled {
                let sample = await Task.detached(priority: .utility) { Self.sample(pid: pid, bundlePath: bundleURL?.path) }.value
                guard !Task.isCancelled else { return }
                guard let sample else { receive(nil); return }
                if let previous, sample.rootBirth != previous.rootBirth { receive(nil); return }
                var cpu: Double?
                if let previous, sample.time > previous.time {
                    var ticks: Double = 0
                    for (id, stat) in sample.stats {
                        if let old = previous.stats[id], old.birth == stat.birth, stat.cpu >= old.cpu {
                            ticks += Double(stat.cpu - old.cpu)
                        }
                    }
                    // Both proc_taskinfo CPU counters and mach_absolute_time use Mach ticks.
                    cpu = max(0, 100 * ticks / Double(sample.time - previous.time))
                }
                receive(AppResourceUsage(cpuPercent: cpu, residentBytes: sample.stats.values.reduce(0) { $0 + $1.memory }))
                previous = sample
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }
    private struct Stat: Sendable { let cpu: UInt64; let memory: UInt64; let birth: UInt64 }
    private struct Sample: Sendable { let time: UInt64; let rootBirth: UInt64; let stats: [pid_t: Stat] }
    private nonisolated static func sample(pid: pid_t, bundlePath: String?) -> Sample? {
        var root = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &root, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: min(Int(count) + 128, 32768))
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.size)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, bytes) }
        guard actual > 0 else { return nil }
        var parents: [pid_t: pid_t] = [:], births: [pid_t: UInt64] = [:]
        var members: Set<pid_t> = [pid]
        for id in pids.prefix(min(Int(actual), pids.count)) where id > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(id, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { continue }
            parents[id] = pid_t(info.pbi_ppid)
            births[id] = info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
            // Include app-bundled helpers even if launchd has reparented them.
            if let bundlePath {
                var path = [CChar](repeating: 0, count: 4096 /* PROC_PIDPATHINFO_MAXSIZE: 4 * MAXPATHLEN */)
                let length = path.withUnsafeMutableBytes { proc_pidpath(id, $0.baseAddress, UInt32($0.count)) }
                if length > 0, String(cString: path).hasPrefix(bundlePath + "/") { members.insert(id) }
            }
        }
        var changed = true
        while changed {
            changed = false
            for (child, parent) in parents where members.contains(parent) && !members.contains(child) {
                members.insert(child); changed = true
            }
        }
        var stats: [pid_t: Stat] = [:]
        for id in members {
            var info = proc_taskinfo()
            guard proc_pidinfo(id, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size else { continue }
            stats[id] = Stat(cpu: info.pti_total_user + info.pti_total_system, memory: info.pti_resident_size, birth: births[id] ?? 0)
        }
        guard stats[pid] != nil else { return nil }
        return Sample(time: mach_absolute_time(), rootBirth: root.pbi_start_tvsec * 1_000_000 + root.pbi_start_tvusec, stats: stats)
    }
    deinit { task?.cancel() }
}
