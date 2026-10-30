import AppKit
import Combine
import ScreenCaptureKit
import CoreVideo

/// Immediate cached images with bounded asynchronous ScreenCaptureKit refreshes.
@MainActor public final class ThumbnailService: ObservableObject {
    private struct Entry { let image: CGImage; let capturedAt: Date; var used: UInt64 }
    @Published public private(set) var revision: UInt64 = 0
    public var capacity = 150
    private var cache: [CGWindowID: Entry] = [:]
    private var clock: UInt64 = 0
    private var content: SCShareableContent?
    private var contentDate = Date.distantPast
    private var contentTask: Task<SCShareableContent, Error>?
    private var contentInvalidated = true
    private var requests: [CGWindowID: Task<CGImage?, Never>] = [:]
    private let gate = CaptureGate(limit: 4)
    private var visibleTask: Task<Void, Never>?
    public init() {}
    public func cachedImage(for id: CGWindowID) -> CGImage? {
        guard var entry = cache[id] else { return nil }
        clock &+= 1; entry.used = clock; cache[id] = entry
        return entry.image
    }
    public func capturedAt(for id: CGWindowID) -> Date? { cache[id]?.capturedAt }
    public func invalidateShareableContent() { contentInvalidated = true }
    public func remove(windowID: CGWindowID) { cache.removeValue(forKey: windowID); revision &+= 1 }
    private func shareableContent() async throws -> SCShareableContent {
        if let contentTask { return try await contentTask.value }
        if let content, !contentInvalidated || Date().timeIntervalSince(contentDate) < 1 { return content }
        if Date().timeIntervalSince(contentDate) < 1, let content { return content }
        contentDate = Date()
        let task = Task { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
        contentTask = task
        do {
            let result = try await task.value
            content = result; contentInvalidated = false; contentTask = nil
            return result
        } catch { contentTask = nil; throw error }
    }
    /// Retains the previous image if a window is minimized, inaccessible, or capture fails.
    @discardableResult public func refresh(windowID: CGWindowID, size: CGSize = CGSize(width: 320, height: 200), scale: CGFloat = 2) async -> CGImage? {
        if let request = requests[windowID] { return await request.value }
        let task = Task<CGImage?, Never> { [weak self] in
            guard let self else { return nil }
            await self.gate.acquire()
            if Task.isCancelled { await self.gate.release(); return self.cachedImage(for: windowID) }
            let result: CGImage?
            do {
                guard CGPreflightScreenCaptureAccess() else { await self.gate.release(); return self.cachedImage(for: windowID) }
                let content = try await self.shareableContent()
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    self.contentInvalidated = true
                    await self.gate.release(); return self.cachedImage(for: windowID)
                }
                let config = SCStreamConfiguration()
                let ratio = max(window.frame.width, 1) / max(window.frame.height, 1)
                let width = min(max(size.width, 1), max(size.height, 1) * ratio)
                let height = width / ratio
                config.width = min(2048, max(1, Int(width * max(scale, 1))))
                config.height = min(2048, max(1, Int(height * max(scale, 1))))
                config.showsCursor = false
                config.capturesShadowsOnly = false
                config.ignoreShadowsSingleWindow = true
                config.pixelFormat = kCVPixelFormatType_32BGRA
                result = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
            } catch { result = nil }
            await self.gate.release()
            if let result, result.width > 1, result.height > 1, Self.hasVisiblePixels(result) {
                self.clock &+= 1
                self.cache[windowID] = Entry(image: result, capturedAt: Date(), used: self.clock)
                while self.cache.count > max(1, self.capacity), let oldest = self.cache.min(by: { $0.value.used < $1.value.used })?.key { self.cache.removeValue(forKey: oldest) }
                self.revision &+= 1
            }
            return self.cachedImage(for: windowID)
        }
        requests[windowID] = task
        let result = await task.value
        requests[windowID] = nil
        return result
    }
    public func startRefreshingVisible(windowIDs: [CGWindowID], interval: TimeInterval = 1, size: CGSize = CGSize(width: 320, height: 200), scale: CGFloat = 2) {
        visibleTask?.cancel()
        visibleTask = Task { [weak self] in
            repeat {
                guard let self, !Task.isCancelled else { return }
                await withTaskGroup(of: Void.self) { group in
                    for id in windowIDs { group.addTask { _ = await self.refresh(windowID: id, size: size, scale: scale) } }
                }
                guard interval > 0 else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, interval) * 1_000_000_000))
            } while !Task.isCancelled
        }
    }
    public func stopRefreshingVisible() {
        visibleTask?.cancel(); visibleTask = nil
        for task in requests.values { task.cancel() }
    }
    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 8, height: 8, bitsPerComponent: 8,
                bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
        }
    }
}

private actor CaptureGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }
    func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { active -= 1 } else { waiters.removeFirst().resume() }
    }
}
