import AppKit
import ApplicationServices
import Combine
import Security
import os

/// What the onboarding and Settings rows can truthfully say about one permission.
/// `false` from the system check alone means "this process has no access", never "this build cannot get access".
public enum PermissionAccess: Equatable, Sendable {
    /// The first system check has not answered yet.
    case checking
    /// The current process has access.
    case granted
    /// DogBar has never asked. This is the normal first-launch state.
    case notRequested
    /// A user-initiated request is registering DogBar with macOS.
    case requesting
    /// DogBar asked and macOS still reports no access. The user must turn DogBar on in System Settings.
    /// Screen Recording only reaches a process started after the switch is on, so the user should then Quit & Reopen.
    case waitingForUser
}

/// Where the running bundle lives. Privacy grants should be made for the copy the user keeps.
public enum InstallLocation: Equatable, Sendable {
    case installed
    /// Running from a mounted disk image or another read-only volume.
    case diskImage
    /// Gatekeeper runs a quarantined app from a randomized read-only path until it is moved, e.g. into Applications.
    case translocated
    public var isInstalled: Bool { self == .installed }

    public static func classify(bundlePath: String, isReadOnlyVolume: Bool) -> InstallLocation {
        if bundlePath.contains("/AppTranslocation/") { return .translocated }
        if isReadOnlyVolume { return .diskImage }
        return .installed
    }

    /// One `stat`-level metadata read. Safe on the main thread.
    public static func current(bundle: Bundle = .main) -> InstallLocation {
        let url = bundle.bundleURL
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return classify(bundlePath: url.path, isReadOnlyVolume: readOnly)
    }
}

/// Permission checks never enable invasive features by themselves.
/// Polling only reads access. Only the explicit `open…` actions request it, at most once per process and permission.
@MainActor public final class PermissionsService: ObservableObject {
    @Published public private(set) var accessibility = false
    @Published public private(set) var screenRecording = false
    @Published public private(set) var usesAdHocSigning: Bool
    @Published public private(set) var hasCheckedPermissions = false
    @Published public private(set) var installLocation: InstallLocation
    @Published private var requests: [Kind: RequestState] = [:]
    public var isChecking: Bool { !hasCheckedPermissions }
    public var isGranted: Bool { hasCheckedPermissions && accessibility && screenRecording }
    public var accessibilityAccess: PermissionAccess { access(.accessibility, granted: accessibility) }
    public var screenRecordingAccess: PermissionAccess { access(.screenRecording, granted: screenRecording) }
    /// True after a request in this process that has not produced access yet.
    /// Turning Screen Recording on now needs a new process, so offer Quit & Reopen.
    public var screenRecordingNeedsRelaunchAfterGrant: Bool {
        hasCheckedPermissions && !screenRecording && requests[.screenRecording]?.requestedThisProcess == true
    }

    enum Kind: String { case accessibility, screenRecording
        var pane: String { self == .accessibility ? "Privacy_Accessibility" : "Privacy_ScreenCapture" }
        var defaultsKey: String { "PermissionsService.requested.\(rawValue)" }
    }
    private struct RequestState: Equatable {
        var inFlight = false, requestedThisProcess = false, settingsOpened = false
    }

    private let checkAccessibility: () -> Bool
    private let checkScreenRecording: () -> Bool
    private let requestAccessibility: () -> Void
    private let requestScreenRecording: () -> Void
    private let showSettings: (String) -> Void
    private let workerQueue: DispatchQueue?
    private let requestQueue: DispatchQueue?
    private let checkSigning: (() -> Bool)?
    private let defaults: UserDefaults?
    private let settingsFallbackDelay: Duration
    private var isProbeInFlight = false
    private var signingWasChecked = false
    private var lastProbeAt = Date.distantPast

    public convenience init() {
        self.init(checkAccessibility: { AXIsProcessTrusted() }, checkScreenRecording: { CGPreflightScreenCaptureAccess() }, requestAccessibility: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }, requestScreenRecording: { _ = CGRequestScreenCaptureAccess() }, showSettings: { pane in
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
        }, workerQueue: DispatchQueue(label: "dev.hristijan.dogbar.permissions", qos: .userInitiated),
           requestQueue: DispatchQueue(label: "dev.hristijan.dogbar.permission-requests", qos: .userInitiated),
           checkSigning: Self.isAdHocSigned, defaults: .standard, installLocation: InstallLocation.current())
    }
    /// `requestQueue` defaults to a private serial queue when `workerQueue` is set, so a request that waits on a
    /// system alert can never starve status polling.
    internal init(checkAccessibility: @escaping () -> Bool, checkScreenRecording: @escaping () -> Bool,
                  requestAccessibility: @escaping () -> Void, requestScreenRecording: @escaping () -> Void,
                  showSettings: @escaping (String) -> Void, usesAdHocSigning: Bool = false,
                  workerQueue: DispatchQueue? = nil, requestQueue: DispatchQueue? = nil, checkSigning: (() -> Bool)? = nil,
                  defaults: UserDefaults? = nil, installLocation: InstallLocation = .installed,
                  settingsFallbackDelay: Duration = .seconds(2)) {
        self.checkAccessibility = checkAccessibility; self.checkScreenRecording = checkScreenRecording
        self.requestAccessibility = requestAccessibility; self.requestScreenRecording = requestScreenRecording
        self.showSettings = showSettings; self.usesAdHocSigning = usesAdHocSigning
        self.workerQueue = workerQueue; self.checkSigning = checkSigning
        self.requestQueue = requestQueue ?? workerQueue.map { _ in DispatchQueue(label: "dev.hristijan.dogbar.permission-requests", qos: .userInitiated) }
        self.defaults = defaults; self.installLocation = installLocation; self.settingsFallbackDelay = settingsFallbackDelay
        refresh()
    }
    /// Polling only reads effective access. A Settings toggle can refer to an older process.
    public func refresh() {
        // Preflight can perform synchronous TCC IPC. Never hold up the first window on it.
        guard !isProbeInFlight else { return }
        if workerQueue != nil, Date().timeIntervalSince(lastProbeAt) < 0.75 { return }
        lastProbeAt = Date(); isProbeInFlight = true
        let accessibilityProbe = checkAccessibility, recordingProbe = checkScreenRecording
        let signingProbe = signingWasChecked ? nil : checkSigning
        if let workerQueue {
            workerQueue.async { [weak self] in
                let accessibility = accessibilityProbe(), recording = recordingProbe(), adHoc = signingProbe?()
                Task { @MainActor [weak self] in self?.apply(accessibility: accessibility, screenRecording: recording, adHoc: adHoc) }
            }
        } else {
            apply(accessibility: accessibilityProbe(), screenRecording: recordingProbe(), adHoc: signingProbe?())
        }
    }
    private func apply(accessibility: Bool, screenRecording: Bool, adHoc: Bool?) {
        let changed = !hasCheckedPermissions || self.accessibility != accessibility || self.screenRecording != screenRecording
        if self.accessibility != accessibility { self.accessibility = accessibility }
        if self.screenRecording != screenRecording { self.screenRecording = screenRecording }
        if let adHoc { usesAdHocSigning = adHoc }
        signingWasChecked = true
        if !hasCheckedPermissions { hasCheckedPermissions = true }
        isProbeInFlight = false
        if changed {
            record("Effective permissions: accessibility=\(accessibility), screenRecording=\(screenRecording), adHoc=\(usesAdHocSigning), install=\(installLocation), pid=\(ProcessInfo.processInfo.processIdentifier), bundle=\(Bundle.main.bundlePath)")
        }
    }
    /// User action. Asks macOS once per process, then opens the pane after DogBar is registered in it.
    public func openAccessibility() { open(.accessibility, granted: accessibility, request: requestAccessibility) }
    /// User action. Asks macOS once per process, then opens the pane after DogBar is registered in it.
    public func openScreenRecording() { open(.screenRecording, granted: screenRecording, request: requestScreenRecording) }

    private func access(_ kind: Kind, granted: Bool) -> PermissionAccess {
        guard hasCheckedPermissions else { return .checking }
        if granted { return .granted }
        let state = requests[kind] ?? RequestState()
        if state.inFlight { return .requesting }
        if state.requestedThisProcess || defaults?.bool(forKey: kind.defaultsKey) == true { return .waitingForUser }
        return .notRequested
    }
    private func open(_ kind: Kind, granted: Bool, request: @escaping () -> Void) {
        var state = requests[kind] ?? RequestState()
        // A request is already registering: repeated clicks must not stack prompts or Settings windows.
        if state.inFlight { return }
        // Granted, or already asked in this process: macOS will not prompt again, so go straight to Settings.
        if granted || state.requestedThisProcess { showSettings(kind.pane); refresh(); return }
        state.inFlight = true; state.requestedThisProcess = true; state.settingsOpened = false
        requests[kind] = state
        defaults?.set(true, forKey: kind.defaultsKey)
        record("Requesting \(kind.rawValue) access, install=\(installLocation)")
        // Opening the pane only after the request returns ensures DogBar is already listed there.
        guard let requestQueue else { request(); finishRequest(kind); return }
        requestQueue.async { [weak self] in
            request()
            Task { @MainActor [weak self] in self?.finishRequest(kind) }
        }
        // If the request call waits on a system alert, still give the user the pane.
        let delay = settingsFallbackDelay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.requests[kind]?.inFlight == true else { return }
            self.openSettingsOnce(kind)
        }
    }
    private func finishRequest(_ kind: Kind) {
        requests[kind]?.inFlight = false
        openSettingsOnce(kind)
        lastProbeAt = .distantPast; refresh()
    }
    private func openSettingsOnce(_ kind: Kind) {
        guard requests[kind]?.settingsOpened == false else { return }
        requests[kind]?.settingsOpened = true
        showSettings(kind.pane)
    }
    private func record(_ message: String) {
        Log.system.info("\(message, privacy: .public)")
        DiagnosticsService.record(message)
    }
    nonisolated private static func isAdHocSigned() -> Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let values = information as? [String: Any],
              let flags = values[kSecCodeInfoFlags as String] as? NSNumber else { return false }
        return flags.uint32Value & 0x2 != 0
    }
}
public enum Log {
    public static let system = Logger(subsystem: "dev.hristijan.dogbar", category: "system")
}
