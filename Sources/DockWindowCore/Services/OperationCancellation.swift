import Foundation

/// Bridges cooperative task cancellation into queued synchronous work.
/// Cancellation cannot retract a command that has already reached another process.
internal final class OperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
