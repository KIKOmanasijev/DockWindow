import ApplicationServices
import Foundation

/// Private process-front and key-window operations, loaded without a private link dependency.
public final class ProcessFocus {
    public static let shared = ProcessFocus()
    private typealias PSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias Front = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32
    private typealias Post = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
    private let psn = RuntimeSymbols.load(["GetProcessForPID"], as: PSN.self)
    private let front = RuntimeSymbols.load(["_SLPSSetFrontProcessWithOptions"], as: Front.self)
    private let post = RuntimeSymbols.load(["SLPSPostEventRecordTo"], as: Post.self)
    public var availability: [String: Bool] { ["GetProcessForPID": psn != nil, "_SLPSSetFrontProcessWithOptions": front != nil, "SLPSPostEventRecordTo": post != nil] }
    public var isAvailable: Bool { psn != nil && front != nil && post != nil }
    private init() {}
    /// Fronts a specific window with mode 0x200 and sends a key-focus record to that window ID.
    /// Record fields verified against upstream CGSEvent declarations. No mouse-up is synthesized.
    @discardableResult public func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard isAvailable else { return false }
        var serial = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        guard psn?(pid, &serial) == 0, front?(&serial, windowID, 0x200) == 0 else { return false }
        var record = [UInt8](repeating: 0, count: 256)
        record[4] = 248
        record[8] = 1
        record[58] = 16
        var identifier = windowID
        var point = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &identifier) { record.replaceSubrange(60..<64, with: $0) }
        withUnsafeBytes(of: &point) { record.replaceSubrange(32..<48, with: $0) }
        return record.withUnsafeMutableBufferPointer { buffer in
            guard let address = buffer.baseAddress else { return false }
            return post?(&serial, address) == 0
        }
    }
}
