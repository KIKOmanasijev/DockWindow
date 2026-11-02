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
            statusHero
            SettingsSection("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { setLogin($0) }))
                    .settingsDescription(loginDescription)
                    .disabled(loginBusy || loginStatusChecking)
                    .settingsAnchor("general.login")
                if loginStatus == .requiresApproval {
                    SettingsRow("Approval required", description: "Approve DogBar in System Settings to finish turning this on.") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    .settingsDescription("The paw menu. When hidden, open DogBar again to reach Settings.")
                    .settingsAnchor("general.menubar")
                Toggle("Show DogBar in the Dock", isOn: $settings.showDogBarInDock)
                    .settingsDescription("DogBar’s own icon, in either Dock.")
                    .settingsAnchor("general.dockicon")
            }
            SettingsSection("Updates") {
                Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
                    .settingsDescription("About once a day. Nothing installs until you choose Install and Relaunch.")
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
                    .settingsDescription("Off unless you choose it. Never window titles, app names, files or typing.")
                    .settingsAnchor("general.usage")
                SettingsMore("general.privacy.more", title: "What’s shared") {
                    SettingsDescriptionText("A random install ID, the app and macOS versions, whether setup finished, and which features were used each day. It helps decide what to improve.")
                }
            }
            SettingsSection("Recovery") {
                SettingsRow("Apple’s Dock", description: "Put it back exactly as it was. DogBar’s Dock turns off.") {
                    Button("Restore Apple’s Dock", action: onRestoreNativeDock)
                }
                .settingsAnchor("general.restore")
                SettingsRow("Reset", description: "Default settings. Dock backups and pins are kept.") {
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

    /// The one place the dog appears on this page: DogBar's state, the way out of an unfinished
    /// setup, and the pause switch in the same strip as every other main switch.
    private var statusHero: some View {
        let (title, detail, tone): (String, String, SettingsStatusPill.Tone) = switch status {
        case .running: ("DogBar is running", settings.useDogBarDock ? "Your Dock, previews and switcher are on." : "Previews and the switcher are on, with Apple’s Dock.", .good)
        case .paused: ("DogBar is paused", "Apple’s Dock is back. Everything resumes when you turn this off.", .warning)
        case .setup: ("Setup isn’t finished", "DogBar starts by itself once both permissions are allowed.", .warning)
        case .checking: ("Checking permissions…", "This only takes a moment.", .neutral)
        }
        return SettingsHero(title: title, text: detail) {
            SettingsMascot(pose: .guide, size: 112)
                .frame(width: 140, height: 104)
        } detail: {
            HStack(spacing: 10) {
                SettingsStatusPill(text: statusWord, symbol: statusSymbol, tone: tone)
                if status == .setup {
                    Button("Finish Setup…", action: onShowPermissions).buttonStyle(.glassProminent)
                }
            }
            .padding(.top, 3)
        } control: {
            Toggle("Pause DogBar", isOn: $settings.isPaused)
                .settingsDescription("Brings Apple’s Dock back and stops DogBar until you resume.")
                .accessibilityHint("Suspends DogBar and restores Apple's Dock while paused.")
        }
        .settingsAnchor("general.pause")
    }
    private var statusSymbol: String? {
        switch status {
        case .running: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .setup: return "exclamationmark.triangle.fill"
        case .checking: return nil
        }
    }
    private var statusWord: String {
        switch status {
        case .running: return "Running"
        case .paused: return "Paused"
        case .setup: return "Needs permissions"
        case .checking: return "Checking"
        }
    }

    private var loginDescription: String {
        if loginStatusChecking { return "Start DogBar when you sign in. Checking status…" }
        switch loginStatus {
        case .enabled: return "Start DogBar when you sign in. On."
        case .requiresApproval: return "Start DogBar when you sign in. Waiting for your approval."
        case .notFound: return "Start DogBar when you sign in. macOS can’t find DogBar’s login item."
        default: return "Start DogBar when you sign in."
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
