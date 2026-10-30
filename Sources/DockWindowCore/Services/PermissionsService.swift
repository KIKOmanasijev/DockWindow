import AppKit
import ApplicationServices
import Combine
import os

/// Permission checks never enable invasive features by themselves.
@MainActor public final class PermissionsService: ObservableObject {
    @Published public private(set) var accessibility = false
    @Published public private(set) var screenRecording = false
    public var isGranted: Bool { accessibility && screenRecording }
    public init() { refresh() }
    public func refresh() { accessibility = AXIsProcessTrusted(); screenRecording = CGPreflightScreenCaptureAccess() }
    public func openAccessibility() { open("Privacy_Accessibility") }
    public func openScreenRecording() { open("Privacy_ScreenCapture") }
    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}
public enum Log {
    public static let system = Logger(subsystem: "com.dockwindow.app", category: "system")
}
