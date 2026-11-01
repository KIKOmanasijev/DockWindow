import Foundation

/// Update channel baked into the signed bundle's Info.plist by the packaging scripts.
/// The signed bundle is the trusted source; user defaults cannot change it.
public enum UpdateChannel: String, Sendable {
    /// Notarized Developer ID releases. Sees only untagged (stable) feed items.
    case stable
    /// Self-signed previews and local development builds. Also sees items tagged `preview`.
    case preview

    public var allowedFeedChannels: Set<String> { self == .preview ? ["preview"] : [] }
}

/// Update settings read from the app's own Info.plist. Missing or inconsistent metadata
/// disables the updater instead of guessing.
public struct UpdateConfiguration: Equatable, Sendable {
    public static let origin = "dogbar.hristijan.dev"
    public static let feedURL = URL(string: "https://dogbar.hristijan.dev/appcast.xml")!

    public let channel: UpdateChannel
    public let build: Int
    public let publicKey: String

    public init?(info: [String: Any]) {
        guard let raw = info["DogBarUpdateChannel"] as? String, let channel = UpdateChannel(rawValue: raw),
              let buildText = info["CFBundleVersion"] as? String, let build = UpdatePolicy.buildNumber(buildText),
              let key = info["SUPublicEDKey"] as? String, UpdatePolicy.isPublicKey(key),
              info["SUFeedURL"] as? String == Self.feedURL.absoluteString,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUAutomaticallyUpdate"] as? Bool == false,
              info["SUAllowsAutomaticUpdates"] as? Bool == false else { return nil }
        self.channel = channel
        self.build = build
        publicKey = key
    }
}

/// An appcast item as Sparkle parsed it, after Sparkle verified the signed feed.
public struct UpdateCandidate: Equatable, Sendable {
    public var fileURL: URL?
    public var build: String
    public var channel: String?
    public var minimumSystemVersion: String?
    public var hardwareRequirements: Set<String>

    public init(fileURL: URL?, build: String, channel: String?, minimumSystemVersion: String?, hardwareRequirements: Set<String>) {
        self.fileURL = fileURL
        self.build = build
        self.channel = channel
        self.minimumSystemVersion = minimumSystemVersion
        self.hardwareRequirements = hardwareRequirements
    }
}

public enum UpdateRejection: Error, Equatable, LocalizedError {
    case untrustedLocation, notNewer, wrongChannel, operatingSystem, architecture

    public var errorDescription: String? {
        switch self {
        case .untrustedLocation: return "The update is not hosted at DogBar's own versioned download location."
        case .notNewer: return "The update is not newer than this build. DogBar never downgrades."
        case .wrongChannel: return "The update belongs to a channel this build does not follow."
        case .operatingSystem: return "The update does not declare a macOS version this Mac can run."
        case .architecture: return "The update is not marked as an Apple Silicon build."
        }
    }
}

/// DogBar's own checks, layered on Sparkle's signed-feed and archive signature checks.
public enum UpdatePolicy {
    public static func buildNumber(_ text: String) -> Int? {
        guard text.range(of: #"^[1-9][0-9]{0,8}$"#, options: .regularExpression) != nil else { return nil }
        return Int(text)
    }

    /// A base64-encoded 32-byte Ed25519 public key.
    public static func isPublicKey(_ text: String) -> Bool {
        guard text.count == 44, let data = Data(base64Encoded: text) else { return false }
        return data.count == 32
    }

    public static func check(_ item: UpdateCandidate, channel: UpdateChannel, currentBuild: Int,
                             runningOS: OperatingSystemVersion) throws {
        guard let url = item.fileURL, url.scheme == "https", url.host == UpdateConfiguration.origin,
              url.port == nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw UpdateRejection.untrustedLocation
        }
        let label = channel == .preview ? #"(?:-preview\.[1-9][0-9]{0,3})?"# : ""
        let pattern = #"^/downloads/DogBar-(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})"# + label + #"-arm64\.dmg$"#
        guard url.path.range(of: pattern, options: .regularExpression) != nil else { throw UpdateRejection.untrustedLocation }
        guard let build = buildNumber(item.build), build > currentBuild else { throw UpdateRejection.notNewer }
        if let tag = item.channel, !channel.allowedFeedChannels.contains(tag) { throw UpdateRejection.wrongChannel }
        guard let minimum = item.minimumSystemVersion, isSupported(minimum: minimum, running: runningOS) else {
            throw UpdateRejection.operatingSystem
        }
        guard item.hardwareRequirements.contains("arm64") else { throw UpdateRejection.architecture }
    }

    static func isSupported(minimum: String, running: OperatingSystemVersion) -> Bool {
        guard minimum.range(of: #"^[0-9]{1,3}(?:\.[0-9]{1,3}){0,2}$"#, options: .regularExpression) != nil else { return false }
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        let required = parts + Array(repeating: 0, count: 3 - parts.count)
        let actual = [running.majorVersion, running.minorVersion, running.patchVersion]
        // A floor below DogBar's own minimum means the feed item was not generated from a real bundle.
        guard required[0] >= 26 else { return false }
        return actual.lexicographicallyPrecedes(required) == false
    }
}

/// State shared between the app's Sparkle controller and the Settings window.
@MainActor public final class UpdatePreferences: ObservableObject {
    @Published public var isAvailable = false
    @Published public var statusText = "Updates are unavailable in this build."
    @Published public var automaticChecks = false {
        didSet { if automaticChecks != oldValue { onAutomaticChecksChanged?(automaticChecks) } }
    }
    public var onAutomaticChecksChanged: ((Bool) -> Void)?
    public var onCheckNow: (() -> Void)?

    public init() {}
}
