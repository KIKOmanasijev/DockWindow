import Foundation

/// Sending a hide request is not evidence that the target became hidden.
@MainActor enum ApplicationHideOperation {
    static func run(isHidden: () -> Bool, isTerminated: () -> Bool,
                    isCancelled: () -> Bool, requestHide: () -> Bool,
                    setAXHidden: () async -> Bool,
                    wait: () async throws -> Void = { try await Task.sleep(nanoseconds: 50_000_000) }) async -> Bool {
        func valid() -> Bool { !Task.isCancelled && !isCancelled() && !isTerminated() }
        guard valid() else { return false }
        if isHidden() { return true }
        _ = requestHide()
        // Even a negative acknowledgement can race a completed hide. AppKit's
        // observable state is refreshed on subsequent main-run-loop turns.
        for _ in 0..<6 {
            do { try await wait() } catch { return false }
            guard valid() else { return false }
            if isHidden() { return true }
        }
        guard valid() else { return false }
        _ = await setAXHidden()
        for _ in 0..<6 {
            do { try await wait() } catch { return false }
            guard valid() else { return false }
            if isHidden() { return true }
        }
        return false
    }
}
