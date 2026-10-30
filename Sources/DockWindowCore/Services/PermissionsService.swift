import AppKit
import ApplicationServices
import Combine
import Security
import os

/// Permission checks never enable invasive features by themselves.
@MainActor public final class PermissionsService: ObservableObject {
    @Published public private(set) var accessibility = false
    @Published public private(set) var screenRecording = false
    public let usesAdHocSigning: Bool
    private let checkAccessibility: () -> Bool
    private let checkScreenRecording: () -> Bool
    private let requestAccessibility: () -> Void
    private let requestScreenRecording: () -> Void
    private let showSettings: (String) -> Void
    public var isGranted: Bool { accessibility && screenRecording }
    public convenience init() {
        self.init(checkAccessibility: { AXIsProcessTrusted() }, checkScreenRecording: { CGPreflightScreenCaptureAccess() }, requestAccessibility: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }, requestScreenRecording: { _ = CGRequestScreenCaptureAccess() }, showSettings: { pane in
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
        }, usesAdHocSigning: Self.isAdHocSigned())
    }
    internal init(checkAccessibility: @escaping () -> Bool, checkScreenRecording: @escaping () -> Bool,
                  requestAccessibility: @escaping () -> Void, requestScreenRecording: @escaping () -> Void,
                  showSettings: @escaping (String) -> Void, usesAdHocSigning: Bool = false) {
        self.checkAccessibility = checkAccessibility; self.checkScreenRecording = checkScreenRecording
        self.requestAccessibility = requestAccessibility; self.requestScreenRecording = requestScreenRecording
        self.showSettings = showSettings; self.usesAdHocSigning = usesAdHocSigning
        refresh()
    }
    /// Polling only reads effective access. A Settings toggle can refer to an older build.
    public func refresh() {
        let accessibility = checkAccessibility(), screenRecording = checkScreenRecording()
        if self.accessibility != accessibility { self.accessibility = accessibility }
        if self.screenRecording != screenRecording { self.screenRecording = screenRecording }
    }
    public func openAccessibility() {
        if !checkAccessibility() { requestAccessibility() }
        showSettings("Privacy_Accessibility"); refresh()
    }
    public func openScreenRecording() {
        if !checkScreenRecording() { requestScreenRecording() }
        showSettings("Privacy_ScreenCapture"); refresh()
    }
    private static func isAdHocSigned() -> Bool {
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
    public static let system = Logger(subsystem: "com.dockwindow.app", category: "system")
}
