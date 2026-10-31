import AppKit
import CryptoKit

/// An explicit, user-initiated update flow. Installation stays in Finder for now.
@MainActor final class UpdateController {
    private var busy = false
    private let origin = URL(string: "https://dogbar.hristijan.dev")!
    private struct Release: Decodable {
        let available: Bool
        let version: String?
        let build: String?
        let url: String?
        let sha256: String?
        let architecture: String?
        let minimumMacOS: String?
        let notarized: Bool
        let channel: String?
        let signing: String?
    }
    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "DogBarPreviewVersion") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    private var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    private func alert(_ title: String, _ message: String, confirm: String? = nil) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = message
        a.addButton(withTitle: confirm ?? "OK")
        if confirm != nil { a.addButton(withTitle: "Cancel") }
        return a.runModal() == .alertFirstButtonReturn
    }
    func check() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                var candidate: Release?
                for feed in ["release.json", "preview.json"] {
                    var request = URLRequest(url: origin.appendingPathComponent(feed), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    try validate(response)
                    guard data.count < 64_000 else { throw UpdateError.invalidFeed }
                    let release = try JSONDecoder().decode(Release.self, from: data)
                    guard release.available else { continue }
                    try validate(release)
                    if isNewer(release) { candidate = release; break }
                }
                guard let release = candidate, let version = release.version, let path = release.url, let hash = release.sha256 else {
                    _ = alert("DogBar is up to date", "Installed: \(currentVersion) (build \(currentBuild)). No newer compatible release is published.")
                    return
                }
                let status = release.notarized ? "Signed public release." : "Self-signed, unnotarized preview. macOS may ask you to confirm opening it."
                guard alert("DogBar \(version) is available", "\(status)\n\nDownload and verify the installer, then drag DogBar into Applications to replace this copy. Your settings are retained when the bundle identity stays the same.", confirm: "Download Update") else { return }
                let url = URL(string: path, relativeTo: origin)!.absoluteURL
                let (temporary, response) = try await URLSession.shared.download(for: URLRequest(url: url, timeoutInterval: 120))
                defer { try? FileManager.default.removeItem(at: temporary) }
                try validate(response)
                let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 200_000_000 else { throw UpdateError.invalidDownload }
                let actual = try await Task.detached { () throws -> String in
                    let handle = try FileHandle(forReadingFrom: temporary)
                    defer { try? handle.close() }
                    var digest = SHA256()
                    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { digest.update(data: chunk) }
                    return digest.finalize().map { String(format: "%02x", $0) }.joined()
                }.value
                guard actual == hash else { throw UpdateError.checksum }
                let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                let destination = folder.appendingPathComponent("DogBar-\(version)-\(UUID().uuidString.prefix(8)).dmg")
                try FileManager.default.moveItem(at: temporary, to: destination)
                guard NSWorkspace.shared.open(destination) else { throw UpdateError.openInstaller }
                _ = alert("Update downloaded and verified", "The installer is open. Quit DogBar from the paw menu so it restores the native Dock, then drag the new DogBar into Applications and open it.\n\nInstaller: \(destination.path)")
            } catch { _ = alert("Could not check or download updates", error.localizedDescription) }
        }
    }
    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let url = response.url, url.scheme == "https", url.host == origin.host,
              url.port == nil, url.user == nil, url.password == nil else { throw UpdateError.invalidDownload }
    }
    private func validate(_ r: Release) throws {
        guard let v = r.version, v.range(of: #"^\d+\.\d+\.\d+(?:-preview\.\d+)?$"#, options: .regularExpression) != nil,
              r.url == "/downloads/DogBar-\(v)-arm64.dmg", r.architecture == "arm64",
              let hash = r.sha256, hash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let os = r.minimumMacOS, os.range(of: #"^\d+\.\d+(?:\.\d+)?$"#, options: .regularExpression) != nil else { throw UpdateError.invalidFeed }
        let runningOS = ProcessInfo.processInfo.operatingSystemVersion
        let running = "\(runningOS.majorVersion).\(runningOS.minorVersion).\(runningOS.patchVersion)"
        guard running.compare(os, options: .numeric) != .orderedAscending else { throw UpdateError.newerOS }
        #if !arch(arm64)
        throw UpdateError.architecture
        #endif
        if !r.notarized {
            guard r.channel == "preview", r.signing == "self-signed", v.contains("-preview."),
                  let b = r.build, let n = Int(b), n > 0 else { throw UpdateError.invalidFeed }
        } else if v.contains("-") { throw UpdateError.invalidFeed }
    }
    private func isNewer(_ r: Release) -> Bool {
        guard let version = r.version else { return false }
        let next = version.components(separatedBy: "-preview.")
        let current = currentVersion.components(separatedBy: "-preview.")
        let order = next[0].compare(current[0], options: .numeric)
        if order != .orderedSame { return order == .orderedDescending }
        if next.count != current.count { return next.count == 1 }
        if next.count == 2, next[1] != current[1] { return next[1].compare(current[1], options: .numeric) == .orderedDescending }
        return (Int(r.build ?? "0") ?? 0) > currentBuild
    }
    private enum UpdateError: LocalizedError {
        case invalidFeed, invalidDownload, checksum, newerOS, architecture, openInstaller
        var errorDescription: String? {
            switch self {
            case .invalidFeed: return "The update feed has invalid or unsupported release metadata. No update was installed."
            case .invalidDownload: return "The update server returned an unexpected response. No update was installed."
            case .checksum: return "The installer checksum did not match the release. The download was discarded."
            case .newerOS: return "This release requires a newer version of macOS."
            case .architecture: return "The published installer currently supports Apple Silicon only."
            case .openInstaller: return "The verified installer was saved in Downloads, but could not be opened."
            }
        }
    }
}
