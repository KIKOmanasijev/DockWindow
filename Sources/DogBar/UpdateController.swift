import AppKit
import CryptoKit
import DogBarCore
import DogBarSparkleBridge
import Security

/// Sparkle 2 updates: a signed appcast, EdDSA-signed archives verified before extraction, and
/// installation only after the person chooses Install and Relaunch. Installing quits DogBar
/// with a normal quit event, so applicationShouldTerminate restores the native Dock first.
///
/// DogBar does not link Sparkle. The embedded framework is loaded only after its signature,
/// including nested helpers, is checked against the same leaf certificate as this app.
@MainActor final class UpdateController: NSObject {
    let preferences = UpdatePreferences()
    /// True while Sparkle should not ask about automatic checks yet.
    var deferPermissionPrompt: (() -> Bool)?
    private let configuration = UpdateConfiguration(info: Bundle.main.infoDictionary ?? [:])
    private var controller: NSObject?
    private var updater: NSObject? { controller?.value(forKey: "updater") as? NSObject }
    private var unavailableReason = "This build has no update configuration. Install DogBar from dogbar.hristijan.dev to receive updates."
    private nonisolated static let observedKey = "automaticallyChecksForUpdates"

    func start() {
        guard controller == nil else { return }
        guard let configuration else { return disable(unavailableReason) }
        do {
            let framework = try Self.verifiedFramework()
            guard let bundle = Bundle(url: framework), bundle.load(),
                  let controller = DogBarSparkleBridge.makeStandardUpdaterController(withUpdaterDelegate: self),
                  let updater = controller.value(forKey: "updater") as? NSObject else { throw UpdateSetupError.unavailable }
            self.controller = controller
            // A feed URL left in user defaults by older Sparkle APIs must never override the bundle.
            _ = updater.perform(NSSelectorFromString("clearFeedURLFromUserDefaults"))
            controller.perform(NSSelectorFromString("startUpdater"))
            updater.addObserver(self, forKeyPath: Self.observedKey, options: [.initial, .new], context: nil)
            preferences.isAvailable = true
            preferences.statusText = configuration.channel == .preview
                ? "Preview channel. Self-signed, unnotarized previews and stable releases, verified with DogBar's update key."
                : "Stable channel. Signed releases verified with DogBar's update key."
            preferences.onAutomaticChecksChanged = { [weak self] enabled in
                self?.updater?.setValue(enabled, forKey: Self.observedKey)
            }
            preferences.onCheckNow = { [weak self] in self?.check() }
        } catch {
            Log.system.error("Updater unavailable: \(error.localizedDescription)")
            disable("Updates are unavailable: \(error.localizedDescription)")
        }
    }

    func check() {
        guard let controller else {
            NSApp.activate()
            let alert = NSAlert(); alert.messageText = "Updates are unavailable"; alert.informativeText = unavailableReason
            alert.runModal()
            return
        }
        controller.perform(NSSelectorFromString("checkForUpdates:"), with: nil)
    }

    private func disable(_ reason: String) {
        unavailableReason = reason
        preferences.isAvailable = false
        preferences.statusText = reason
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == Self.observedKey, let enabled = change?[.newKey] as? Bool else { return }
        Task { @MainActor [weak self] in self?.preferences.automaticChecks = enabled }
    }

    // MARK: Framework verification

    private enum UpdateSetupError: LocalizedError {
        case unsigned, framework, signature(OSStatus), unavailable
        var errorDescription: String? {
            switch self {
            case .unsigned: return "this copy of DogBar is not signed with a certificate."
            case .framework: return "the embedded Sparkle framework is missing or misplaced."
            case .signature(let status): return "the embedded Sparkle framework failed its code signature check (\(status))."
            case .unavailable: return "the embedded Sparkle framework could not be started."
            }
        }
    }

    /// Requires Contents/Frameworks/Sparkle.framework, a real directory signed by this app's
    /// leaf certificate, with every nested helper valid. Self-signed builds disable library
    /// validation, so this check is what keeps a substituted framework from loading.
    private static func verifiedFramework() throws -> URL {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let framework = contents.appendingPathComponent("Frameworks/Sparkle.framework", isDirectory: true)
        let values = try? framework.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isDirectory == true, values?.isSymbolicLink == false,
              framework.resolvingSymlinksInPath().path == framework.standardizedFileURL.path else { throw UpdateSetupError.framework }
        let leaf = try ownLeafCertificateSHA1()
        var requirement: SecRequirement?
        let text = "identifier \"org.sparkle-project.Sparkle\" and certificate leaf = H\"\(leaf)\""
        var status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else { throw UpdateSetupError.signature(status) }
        var code: SecStaticCode?
        status = SecStaticCodeCreateWithPath(framework as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw UpdateSetupError.signature(status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else { throw UpdateSetupError.signature(status) }
        return framework
    }

    private static func ownLeafCertificateSHA1() throws -> String {
        var running: SecCode?
        var code: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { throw UpdateSetupError.unsigned }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: SPUUpdaterDelegate (selectors from the pinned Sparkle 2.10.1 headers)

extension UpdateController {
    @objc(feedURLStringForUpdater:) func feedURLString(for updater: NSObject) -> String? {
        UpdateConfiguration.feedURL.absoluteString
    }

    /// Sparkle's own "check automatically?" question waits until onboarding is finished, so it
    /// never covers the first-run tour. Sparkle asks again on a later launch.
    @objc(updaterShouldPromptForPermissionToCheckForUpdates:) func shouldPromptForPermission(_ updater: NSObject) -> Bool {
        !(deferPermissionPrompt?() ?? false)
    }

    @objc(allowedChannelsForUpdater:) func allowedChannels(for updater: NSObject) -> Set<String> {
        configuration?.channel.allowedFeedChannels ?? []
    }

    @objc(updater:shouldProceedWithUpdate:updateCheck:error:)
    func updater(_ updater: NSObject, shouldProceedWithUpdate item: NSObject, updateCheck: Int) throws {
        guard let configuration else { throw UpdateRejection.wrongChannel }
        let candidate = UpdateCandidate(
            fileURL: item.value(forKey: "fileURL") as? URL,
            build: item.value(forKey: "versionString") as? String ?? "",
            channel: item.value(forKey: "channel") as? String,
            minimumSystemVersion: item.value(forKey: "minimumSystemVersion") as? String,
            hardwareRequirements: item.value(forKey: "hardwareRequirements") as? Set<String> ?? [])
        do {
            try UpdatePolicy.check(candidate, channel: configuration.channel, currentBuild: configuration.build,
                                   runningOS: ProcessInfo.processInfo.operatingSystemVersion)
        } catch {
            Log.system.error("Rejected update build \(candidate.build): \(error.localizedDescription)")
            throw NSError(domain: "dev.hristijan.dogbar.update", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }
    }
}
