import Darwin
import Foundation

/// Replies from the island to a finished Claude Code turn.
///
/// With replies on, Claude Code runs the Stop hook with `asyncRewake: true`: in the background,
/// never blocking the session. The relay opens a private datagram socket next to DogBar's event
/// socket, reports the Stop with that path, and waits. A reply makes it print the text to stderr and
/// exit 2, which Claude Code documents as waking the session and showing the text to Claude. A cancel
/// (the person typed in the terminal instead, the session ended, a newer turn finished) or the
/// timeout makes it exit 0 silently.
public enum AgentReplyChannel {
    public static let argument = "--reply"
    /// Claude Code enforces the hook timeout on asyncRewake hooks; the relay stops waiting a little earlier.
    public static let hookTimeout = 1800
    static let waitLimit: TimeInterval = TimeInterval(hookTimeout - 15)
    public static let maximumReply = 2000

    public struct Message: Codable, Equatable, Sendable {
        public enum Action: String, Codable, Sendable { case reply, cancel }
        public var action: Action
        public var text: String?
        public init(action: Action, text: String? = nil) { self.action = action; self.text = text }
    }

    /// The text Claude sees. Labeled, so the model knows where it came from.
    public static func wakeText(_ reply: String) -> String {
        "The user replied from DogBar's Agent Activity island (treat this as their next message):\n\n\(reply)"
    }

    static let filePrefix = "r-"
    public static func isValidReplyPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.utf8.count < AgentEventSocket.maximumPathBytes, !path.contains("/../") else { return false }
        let name = (path as NSString).lastPathComponent
        guard name.hasPrefix(filePrefix), name.hasSuffix(".sock") else { return false }
        let token = name.dropFirst(filePrefix.count).dropLast(".sock".count)
        return token.count == 12 && token.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    static func makeURL(in directory: URL) -> URL {
        let token = (0..<12).map { _ in String("0123456789abcdef".randomElement()!) }.joined()
        return directory.appendingPathComponent("\(filePrefix)\(token).sock")
    }

    /// Fire-and-forget from DogBar to a waiting relay. False when nothing waits there any more.
    @discardableResult
    public static func send(_ message: Message, to path: String) -> Bool {
        guard isValidReplyPath(path), let data = try? JSONEncoder().encode(message), data.count <= AgentEvent.maximumWireSize else { return false }
        let sent = AgentEventSocket.send(data, to: URL(fileURLWithPath: path))
        // A refused send means the relay is gone (timed out or killed); remove its leftover file.
        if !sent { unlink(path) }
        return sent
    }

    /// Removes reply sockets left behind by relays that were killed. Live ones are kept.
    public static func removeStale(in directory: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(filePrefix) && name.hasSuffix(".sock") {
            let path = directory.appendingPathComponent(name).path
            if !AgentEventSocket.isLive(path) { unlink(path) }
        }
    }

    // MARK: Relay side

    /// A bound reply socket owned by a waiting relay.
    final class Waiter {
        let url: URL
        private let fd: Int32
        init?(directory: URL) {
            let url = AgentReplyChannel.makeURL(in: directory)
            guard var address = AgentEventSocket.address(url.path) else { return nil }
            let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
            guard fd >= 0 else { return nil }
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0 else { close(fd); return nil }
            chmod(url.path, 0o600)
            self.url = url; self.fd = fd
        }
        deinit { close(fd); unlink(url.path) }

        /// Blocks until a valid message arrives or the deadline passes.
        func wait(timeout: TimeInterval) -> Message? {
            let deadline = Date().addingTimeInterval(timeout)
            var buffer = [UInt8](repeating: 0, count: AgentEvent.maximumWireSize + 1)
            while true {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { return nil }
                var interval = timeval(tv_sec: Int(min(remaining, 60)), tv_usec: 0)
                if interval.tv_sec == 0 { interval.tv_usec = 200_000 }
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
                let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
                guard count > 0, count <= AgentEvent.maximumWireSize else { continue }
                guard var message = try? JSONDecoder().decode(Message.self, from: Data(buffer[0..<count])) else { continue }
                if message.action == .reply {
                    message.text = AgentEvent.clean(message.text, limit: maximumReply, singleLine: false)
                    guard message.text != nil else { continue }
                }
                return message
            }
        }
    }
}
