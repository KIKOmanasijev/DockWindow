import AppKit
import ApplicationServices
import Combine
import Security
import os

/// Permission checks never enable invasive features by themselves.
@MainActor public final class PermissionsService: ObservableObject {
    @Published public private(set) var accessibility = false
    @Published public private(set) var screenRecording = false
    @Published public private(set) var usesAdHocSigning: Bool
    @Published public private(set) var hasCheckedPermissions = false
    public var isChecking: Bool { !hasCheckedPermissions }
    private let checkAccessibility: () -> Bool
    private let checkScreenRecording: () -> Bool
    private let requestAccessibility: () -> Void
    private let requestScreenRecording: () -> Void
    private let showSettings: (String) -> Void
    private let workerQueue: DispatchQueue?
    private let checkSigning: (() -> Bool)?
    private var isProbeInFlight = false
    private var signingWasChecked = false
    private var lastProbeAt = Date.distantPast
    public var isGranted: Bool { hasCheckedPermissions && accessibility && screenRecording }
    public convenience init() {
        self.init(checkAccessibility: { AXIsProcessTrusted() }, checkScreenRecording: { CGPreflightScreenCaptureAccess() }, requestAccessibility: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }, requestScreenRecording: { _ = CGRequestScreenCaptureAccess() }, showSettings: { pane in
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
        }, workerQueue: DispatchQueue(label: "dev.hristijan.dogbar.permissions", qos: .userInitiated), checkSigning: Self.isAdHocSigned)
    }
    internal init(checkAccessibility: @escaping () -> Bool, checkScreenRecording: @escaping () -> Bool,
                  requestAccessibility: @escaping () -> Void, requestScreenRecording: @escaping () -> Void,
                  showSettings: @escaping (String) -> Void, usesAdHocSigning: Bool = false,
                  workerQueue: DispatchQueue? = nil, checkSigning: (() -> Bool)? = nil) {
        self.checkAccessibility = checkAccessibility; self.checkScreenRecording = checkScreenRecording
        self.requestAccessibility = requestAccessibility; self.requestScreenRecording = requestScreenRecording
        self.showSettings = showSettings; self.usesAdHocSigning = usesAdHocSigning
        self.workerQueue = workerQueue; self.checkSigning = checkSigning
        refresh()
    }
    /// Polling only reads effective access. A Settings toggle can refer to an older build.
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
            let message = "Effective permissions: accessibility=\(accessibility), screenRecording=\(screenRecording), adHoc=\(usesAdHocSigning), pid=\(ProcessInfo.processInfo.processIdentifier), bundle=\(Bundle.main.bundlePath)"
            Log.system.info("\(message, privacy: .public)")
            DiagnosticsService.record(message)
        }
    }
    public func openAccessibility() {
        if !accessibility { performRequest(requestAccessibility) }
        showSettings("Privacy_Accessibility"); refresh()
    }
    public func openScreenRecording() {
        if !screenRecording { performRequest(requestScreenRecording) }
        showSettings("Privacy_ScreenCapture"); refresh()
    }
    private func performRequest(_ request: @escaping () -> Void) {
        guard let workerQueue else { request(); return }
        workerQueue.async { [weak self] in
            request()
            Task { @MainActor [weak self] in self?.lastProbeAt = .distantPast; self?.refresh() }
        }
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
