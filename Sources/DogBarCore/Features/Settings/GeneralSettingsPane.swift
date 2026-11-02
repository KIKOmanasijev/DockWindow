import AppKit
import ServiceManagement
import SwiftUI

@MainActor struct GeneralSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionsService
    @ObservedObject var updates: UpdatePreferences
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
            statusCard
            SettingsSection("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { setLogin($0) }))
                    .settingsDescription("Start DogBar when you sign in. Status: \(loginStatusText)")
                    .disabled(loginBusy || loginStatusChecking)
                    .settingsAnchor("general.login")
                if loginStatus == .requiresApproval {
                    SettingsRow("Approval required", description: "Approve DogBar in System Settings to finish enabling login launch.") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    .settingsDescription("The paw menu. When it's hidden, open DogBar again to reach Settings.")
                    .settingsAnchor("general.menubar")
                Toggle("Show DogBar in the Dock", isOn: $settings.showDogBarInDock)
                    .settingsDescription("Show DogBar's own icon in either Dock. Settings stays in the paw menu when hidden.")
                    .settingsAnchor("general.dockicon")
            }
            permissionsSection
            SettingsSection("Updates") {
                Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
                    .settingsDescription("About once a day, from DogBar's signed feed. Nothing installs until you choose Install and Relaunch.")
                    .disabled(!updates.isAvailable)
                    .settingsAnchor("general.updates")
                SettingsRow("Software update", description: updates.statusText) {
                    Button("Check Now") { updates.onCheckNow?() }.disabled(!updates.isAvailable)
                }
                .settingsAnchor("general.checknow")
            }
            SettingsSection("Privacy") {
                Toggle("Share anonymous usage data", isOn: Binding(
                    get: { settings.telemetryEnabled }, set: { settings.chooseUsageData(share: $0) }))
                    .settingsDescription("Off unless you choose to share. Never window titles, app names, files or typing.")
                    .settingsAnchor("general.usage")
                SettingsMore("general.privacy.more", title: "What's shared") {
                    SettingsDescriptionText("Helps decide what to improve. DogBar sends a random install ID, app and macOS version, whether setup finished, and which features were used each day. Never window titles, app names, files or anything you type.")
                }
            }
            SettingsSection("Recovery") {
                SettingsRow("Apple's Dock", description: "Put Apple's Dock back exactly as it was. DogBar's Dock turns off.") {
                    Button("Restore Apple's Dock", action: onRestoreNativeDock)
                }
                .settingsAnchor("general.restore")
                SettingsRow("Reset", description: "Restore default settings. Dock recovery backups and pins are kept.") {
                    Button("Reset All Settings…", role: .destructive) { resetConfirmation = true }
                        .disabled(loginBusy || loginStatusChecking)
                }
                .settingsAnchor("general.reset")
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

    // MARK: Status

    private enum Status { case running, paused, setup, checking }
    private var status: Status {
        if settings.isPaused { return .paused }
        if !permissions.hasCheckedPermissions { return .checking }
        return permissions.isGranted ? .running : .setup
    }

    /// The one place the dog appears on this page: presenting DogBar's state and its pause switch.
    private var statusCard: some View {
        let (title, detail, color): (String, String, Color) = switch status {
        case .running: ("DogBar is on", settings.useDogBarDock ? "Your Dock, previews and switcher are running." : "Previews and the switcher are running with Apple's Dock.", SettingsPalette.success)
        case .paused: ("DogBar is paused", "Apple's Dock is back and DogBar's features are off until you resume.", SettingsPalette.caution)
        case .setup: ("Setup isn't finished", "Allow both permissions below and DogBar starts by itself.", SettingsPalette.caution)
        case .checking: ("Checking permissions…", "This only takes a moment.", Color.secondary)
        }
        return HStack(spacing: 14) {
            SettingsMascot(pose: .guide, size: 78)
                .padding(.vertical, -6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(title).font(.system(size: 15, weight: .semibold))
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Toggle("Pause", isOn: $settings.isPaused)
                .toggleStyle(.switch)
                .accessibilityLabel("Pause DogBar")
                .accessibilityHint("Suspends DogBar and restores Apple's Dock while paused.")
                .fixedSize()
        }
        .padding(.leading, 10).padding(.trailing, 16).padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SettingsPalette.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(RadialGradient(colors: [SettingsPalette.tint.opacity(0.09), .clear], center: .leading, startRadius: 0, endRadius: 260)))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SettingsPalette.line, lineWidth: 1))
        .settingsAnchor("general.pause")
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        SettingsSection("Permissions") {
            permissionRow("Accessibility", granted: permissions.accessibility,
                          description: "Focus, close and minimize single windows, and keyboard shortcuts.", action: permissions.openAccessibility)
                .settingsAnchor("general.accessibility")
            permissionRow("Screen Recording", granted: permissions.screenRecording,
                          description: "Real window thumbnails. A relaunch may be needed after you allow it.", action: permissions.openScreenRecording)
                .settingsAnchor("general.screenrecording")
            // Shown in full while something is missing; tucked away once everything is allowed.
            if permissions.hasCheckedPermissions && !permissions.isGranted {
                setupRow
                relaunchRow
            } else {
                SettingsMore("general.permissions.more", title: "Setup and relaunch") {
                    setupRow
                    relaunchRow
                }
            }
            if permissions.usesAdHocSigning {
                SettingsDescriptionText("This build is ad-hoc signed. Rebuilds can lose permission grants. Create a DockWindow Dev code-signing certificate in Keychain Access, then rebuild.")
            }
        }
    }
    private var setupRow: some View {
        SettingsRow("Guided setup", description: "Walk through permissions again in the setup window.") {
            Button("Show Setup", action: onShowPermissions)
        }
        .settingsAnchor("general.setup")
    }
    private var relaunchRow: some View {
        SettingsRow("Relaunch", description: "Restart DogBar after permission changes. Apple's Dock is restored first.") {
            Button("Relaunch DogBar") {
                do { try AppRelauncher.relaunch() } catch { errorMessage = error.localizedDescription }
            }
        }
        .settingsAnchor("general.relaunch")
    }

    private func permissionRow(_ title: String, granted: Bool, description: String, action: @escaping () -> Void) -> some View {
        let state = PermissionRowStatus(hasChecked: permissions.hasCheckedPermissions, granted: granted)
        return SettingsRow(title, description: description) {
            HStack(spacing: 10) {
                Label(state.label, systemImage: state.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state == .checking ? Color.secondary : (granted ? SettingsPalette.success : SettingsPalette.caution))
                Button(permissions.hasCheckedPermissions ? (granted ? "Open System Settings" : "Request Access") : "Checking…", action: action)
                    .disabled(!permissions.hasCheckedPermissions || permissions.isChecking)
            }
        }
    }
    private var loginStatusText: String {
        if loginStatusChecking { return "checking…" }
        switch loginStatus {
        case .enabled: return "enabled."
        case .notRegistered: return "not registered."
        case .requiresApproval: return "requires approval."
        case .notFound: return "app service not found."
        @unknown default: return "unknown."
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
                    errorMessage = "Login launch did not reach the requested state. Status: \(loginStatusText)"
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
