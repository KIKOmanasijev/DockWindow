import AppKit
import Foundation

/// A services facade for symbol diagnostics and bounded opt-in file logging.
public enum DiagnosticsService {
    public static var privateAPIAvailability: [String: Bool] {
        SkyLight.shared.availability.merging(AXPrivate.shared.availability, uniquingKeysWith: { first, _ in first })
            .merging(ProcessFocus.shared.availability, uniquingKeysWith: { first, _ in first })
    }
    public static let logFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DogBar", isDirectory: true).appendingPathComponent("DogBar.log")
    private static let sink = DiagnosticFileSink()
    public static func setDebugLogging(_ enabled: Bool) { sink.setEnabled(enabled) }
    public static func record(_ message: String) { sink.append(message) }
    @MainActor public static func revealLogFile() {
        sink.prepare {
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([logFileURL]) }
        }
    }
}

// All mutable logging state and file access are confined to queue.
private final class DiagnosticFileSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.hristijan.dogbar.filelog", qos: .utility)
    private var enabled = false
    func setEnabled(_ enabled: Bool) {
        queue.async {
            guard self.enabled != enabled else { return }
            self.enabled = enabled
            if enabled { self.write("Debug logging enabled") }
        }
    }
    func append(_ message: String) { queue.async { if self.enabled { self.write(message) } } }
    func prepare(_ completion: @escaping () -> Void) {
        queue.async {
            self.ensureFile()
            completion()
        }
    }
    private func ensureFile() {
        let url = DiagnosticsService.logFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
    }
    private func write(_ message: String) {
        let url = DiagnosticsService.logFileURL
        ensureFile()
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attributes[.size] as? NSNumber, size.intValue > 2_000_000 {
            let previous = url.appendingPathExtension("previous")
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: url, to: previous)
            ensureFile()
        }
        guard let data = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n".data(using: .utf8), let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data) } catch { }
    }
}
