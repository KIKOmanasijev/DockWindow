import AppKit

/// A panel-owned refresh lease. Stopping it never cancels another panel's captures.
/// Shares the service cache, deduplication and four-capture gate, but not its singleton visibleTask.
@MainActor public final class VisibleThumbnailSession {
    private let service: ThumbnailService
    private var task: Task<Void, Never>?
    private var ids: Set<CGWindowID> = []
    private var interval: TimeInterval = -1
    private var size: CGSize = .zero
    private var scale: CGFloat = 0
    public init(service: ThumbnailService) { self.service = service }
    public func update(windowIDs: Set<CGWindowID>, interval: TimeInterval, size: CGSize, scale: CGFloat) {
        guard ids != windowIDs || self.interval != interval || self.size != size || self.scale != scale else { return }
        stop()
        ids = windowIDs; self.interval = interval; self.size = size; self.scale = scale
        guard !windowIDs.isEmpty else { return }
        let service = service
        task = Task {
            repeat {
                guard !Task.isCancelled else { return }
                await withTaskGroup(of: Void.self) { group in
                    for id in windowIDs {
                        group.addTask { guard !Task.isCancelled else { return }; _ = await service.refresh(windowID: id, size: size, scale: scale) }
                    }
                }
                guard interval > 0, !Task.isCancelled else { return }
                do { try await Task.sleep(nanoseconds: UInt64(min(3600, max(0.1, interval)) * 1_000_000_000)) }
                catch { return }
            } while !Task.isCancelled
        }
    }
    public func stop() { task?.cancel(); task = nil; ids = []; interval = -1 }
    deinit { task?.cancel() }
}
