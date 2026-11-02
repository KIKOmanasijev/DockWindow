import Darwin
import Foundation

/// Local-only transport between hook relays and DogBar: a Unix datagram socket inside a
/// per-user 0700 directory. One datagram is one event. Nothing listens on a network interface.
public enum AgentEventSocket {
    /// Lets tests and manual end-to-end checks use a private socket instead of the real one.
    public static let environmentOverride = "DOGBAR_AGENT_SOCKET"
    /// The kernel limit for `sun_path`, including the terminating NUL.
    static let maximumPathBytes = 104

    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment[environmentOverride], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("DogBar/AgentActivity/events.sock")
    }

    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < maximumPathBytes else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in bytes.enumerated() { raw[index] = byte }
        }
        return address
    }

    /// Fire-and-forget. Never blocks: when DogBar is not running, or its queue is full, the event is dropped.
    @discardableResult
    public static func send(_ data: Data, to url: URL = defaultURL) -> Bool {
        guard data.count <= AgentEvent.maximumWireSize, var address = address(url.path) else { return false }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var size = Int32(AgentEvent.maximumWireSize * 2)
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let sent = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buffer.baseAddress, buffer.count, MSG_DONTWAIT, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
        return sent == data.count
    }

    /// Whether a live process is bound to the socket. A leftover file from a crash refuses connections.
    static func isLive(_ path: String) -> Bool {
        guard var address = address(path) else { return false }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return result == 0
    }
}

/// Receives events on a dispatch read source: no polling, no work while nothing is sent.
/// Validation happens here; malformed, oversized, unsupported or excessive datagrams are counted and dropped.
@MainActor public final class AgentEventListener {
    public enum Failure: Error, Equatable, Sendable {
        case pathTooLong, directory(String), inUse, socket(String)
        public var message: String {
            switch self {
            case .pathTooLong: return "The socket path is too long for macOS."
            case .directory(let detail): return "DogBar could not prepare its private folder. \(detail)"
            case .inUse: return "Another copy of DogBar is already receiving agent events. Quit it, then turn Agent Activity off and on."
            case .socket(let detail): return "DogBar could not open its local event socket. \(detail)"
            }
        }
    }
    public struct Counters: Equatable, Sendable {
        public var accepted = 0
        public var rejected = 0
        public var rateLimited = 0
    }

    public let url: URL
    public private(set) var isListening = false
    public private(set) var counters = Counters()
    public var onEvent: ((AgentEvent) -> Void)?
    public var onChange: (() -> Void)?
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var windowStart = Date.distantPast
    private var windowCount = 0
    /// More than this per second is not a real agent; protects the main thread from floods.
    static let maximumEventsPerSecond = 200

    public init(url: URL = AgentEventSocket.defaultURL) { self.url = url }

    public func start() throws(Failure) {
        guard !isListening else { return }
        let path = url.path
        guard var address = AgentEventSocket.address(path) else { throw .pathTooLong }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch { throw .directory(error.localizedDescription) }
        if FileManager.default.fileExists(atPath: path) {
            if AgentEventSocket.isLive(path) { throw .inUse }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw .socket(String(cString: strerror(errno))) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let message = String(cString: strerror(errno)); close(fd)
            throw .socket(message)
        }
        chmod(path, 0o600)
        var size = Int32(AgentEvent.maximumWireSize * 64)
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        self.fd = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.drain() } }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
        isListening = true
        onChange?()
    }

    public func stop() {
        guard isListening else { return }
        source?.cancel(); source = nil
        // Remove the path only if it is still ours (another instance may have replaced a stale one).
        unlink(url.path)
        fd = -1
        isListening = false
        onChange?()
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: AgentEvent.maximumWireSize + 1)
        var changed = false
        while true {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, MSG_TRUNC) }
            if count < 0 { break }
            changed = true
            let now = Date()
            if now.timeIntervalSince(windowStart) >= 1 { windowStart = now; windowCount = 0 }
            windowCount += 1
            guard windowCount <= Self.maximumEventsPerSecond else { counters.rateLimited += 1; continue }
            // MSG_TRUNC returns the real datagram length, so oversize input is detected, not truncated into JSON.
            guard count <= AgentEvent.maximumWireSize else { counters.rejected += 1; continue }
            do {
                let event = try AgentEvent.decode(Data(buffer[0..<count]))
                counters.accepted += 1
                onEvent?(event)
            } catch {
                counters.rejected += 1
            }
        }
        if changed { onChange?() }
    }
}
