import AppKit
import ServiceManagement
import SwiftUI

@MainActor struct GeneralSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionsService
    @ObservedObject var visibility: SettingsVisibility
    let onRestoreNativeDock: () -> Void
    let onShowPermissions: () -> Void
    @State private var resetConfirmation = false
    @State private var errorMessage: String?
    @State private var loginStatus = SMAppService.Status.notRegistered
    @State private var loginStatusChecking = true
    @State private var loginStatusRequest = UUID()
    @State private var loginBusy = false

    var body: some View {
        Group {
            SettingsSection("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { setLogin($0) }))
                    .settingsDescription("Start DogBar when you sign in. Status: \(loginStatusText).")
                    .disabled(loginBusy || loginStatusChecking)
                if loginStatus == .requiresApproval {
                    SettingsRow("Approval required", description: "Approve DogBar in System Settings to finish enabling login launch.") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    .settingsDescription("Open Settings by launching DogBar again if the icon is hidden.")
            }
            SettingsSection("Permissions") {
                permissionRow("Accessibility", granted: permissions.accessibility, description: "Allows window focus, controls and keyboard shortcuts.", action: permissions.openAccessibility)
                permissionRow("Screen Recording", granted: permissions.screenRecording, description: "Allows window thumbnails. A relaunch may be needed after granting access.", action: permissions.openScreenRecording)
                SettingsRow("Permission setup", description: "Open the guided permission setup window.") {
                    Button("Show Setup", action: onShowPermissions)
                }
                SettingsRow("Relaunch", description: "Restart the installed app after permission changes, restoring the native Dock first.") {
                    Button("Relaunch DogBar") {
                        do { try AppRelauncher.relaunch() } catch { errorMessage = error.localizedDescription }
                    }
                }
                if permissions.usesAdHocSigning {
                    Text("This build is ad-hoc signed. Rebuilds can lose permission grants. Create a DockWindow Dev code-signing certificate in Keychain Access, then rebuild.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            SettingsSection("Privacy") {
                Toggle("Share anonymous usage data", isOn: $settings.telemetryEnabled)
                    .settingsDescription("Helps decide what to improve. DogBar sends a random install ID, app and macOS version, whether setup finished, and which features were used each day. Never window titles, app names, files or anything you type.")
            }
            SettingsSection("Session") {
                Toggle("Pause DogBar", isOn: $settings.isPaused)
                    .settingsDescription("Suspend features and restore the native Dock while paused.")
                SettingsRow("Native Dock", description: "Restore the original Dock preferences through the app coordinator.") {
                    Button("Restore Native Dock", action: onRestoreNativeDock)
                }
                SettingsRow("Reset", description: "Restore defaults after confirmation, preserving native Dock recovery backups.") {
                    Button("Reset All Settings…", role: .destructive) { resetConfirmation = true }
                        .disabled(loginBusy || loginStatusChecking)
                }
            }
        }
        .task(id: visibility.isVisible) {
            guard visibility.isVisible, !loginBusy else { return }
            let request = UUID(); loginStatusRequest = request
            loginStatusChecking = true
            defer { if loginStatusRequest == request { loginStatusChecking = false } }
            let status = await LoginItemWorker.status()
            guard !Task.isCancelled else { return }
            loginStatus = status
            permissions.refresh()
        }
        .alert("Reset all settings?", isPresented: $resetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { reset() }
        } message: { Text("Restore default preferences. Native Dock recovery backups are preserved. Your imported pin list is kept until you re-import it.") }
        .alert("Settings action failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func permissionRow(_ title: String, granted: Bool, description: String, action: @escaping () -> Void) -> some View {
        let state = PermissionRowStatus(hasChecked: permissions.hasCheckedPermissions, granted: granted)
        return SettingsRow(title, description: description) {
            HStack(spacing: 10) {
                Label(state.label, systemImage: state.symbol)
                    .foregroundStyle(state == .checking ? Color.secondary : (granted ? Color.green : Color.orange))
                Button(permissions.hasCheckedPermissions ? (granted ? "Open System Settings" : "Request Access") : "Checking…", action: action)
                    .disabled(!permissions.hasCheckedPermissions || permissions.isChecking)
            }
        }
    }
    private var loginStatusText: String {
        if loginStatusChecking { return "Checking..." }
        switch loginStatus {
        case .enabled: return "Enabled"
        case .notRegistered: return "Not registered"
        case .requiresApproval: return "Requires approval"
        case .notFound: return "App service not found"
        @unknown default: return "Unknown"
        }
    }
    private func setLogin(_ enabled: Bool, completion: (() -> Void)? = nil) {
        guard !loginBusy else { return }
        loginBusy = true
        Task { @MainActor in
            defer { loginBusy = false }
            do {
                loginStatus = try await LoginItemWorker.setEnabled(enabled)
                let succeeded = enabled ? (loginStatus == .enabled || loginStatus == .requiresApproval) : loginStatus == .notRegistered
                guard succeeded else {
                    errorMessage = "Login launch did not reach the requested state. Status: \(loginStatusText)."
                    return
                }
                settings.launchAtLogin = enabled
                completion?()
            } catch {
                loginStatus = await LoginItemWorker.status()
                errorMessage = error.localizedDescription
            }
        }
    }
    private func reset() {
        guard !loginBusy else { return }
        // The worker checks actual status before unregistering, even if the cached status is stale.
        setLogin(false) { settings.reset(); DiagnosticsService.setDebugLogging(settings.debugLogging) }
    }
}

/// Service Management can make a blocking XPC call. Never query it while constructing a view.
private enum LoginItemWorker {
    static func status() async -> SMAppService.Status {
        await Task.detached(priority: .utility) { SMAppService.mainApp.status }.value
    }
    static func setEnabled(_ enabled: Bool) async throws -> SMAppService.Status {
        try await Task.detached(priority: .utility) {
            let service = SMAppService.mainApp
            if enabled { try service.register() }
            else if service.status != .notRegistered { try await service.unregister() }
            return service.status
        }.value
    }
}
