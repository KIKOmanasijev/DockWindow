import AppKit
import Combine
import ServiceManagement
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", dock = "Dock", switcher = "Window Switcher", previews = "Dock Previews", appearance = "Appearance", advanced = "Advanced"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .dock: return "dock.rectangle"
        case .switcher: return "rectangle.on.rectangle"
        case .previews: return "rectangle.stack"
        case .appearance: return "paintpalette"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

@MainActor struct SettingsRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionsService
    @ObservedObject var visibility: SettingsVisibility
    let pinnedApps: PinnedAppsStore
    let onRestoreNativeDock: () -> Void
    let onShowPermissions: () -> Void
    @State private var pane: SettingsPane? = .general
    @State private var resetConfirmation = false
    @State private var reimportConfirmation = false
    @State private var errorMessage: String?
    @State private var loginStatus = SMAppService.Status.notRegistered
    @State private var loginStatusChecking = true
    @State private var loginStatusRequest = UUID()
    @State private var loginBusy = false
    @State private var subrolesText = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.rawValue, systemImage: pane.symbol).tag(pane)
            }.navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
        } detail: {
            Form {
                switch pane ?? .general {
                case .general: general
                case .dock: DockSettingsPane(settings: settings)
                case .switcher: SwitcherSettingsPane(settings: settings)
                case .previews: PreviewSettingsPane(settings: settings)
                case .appearance: AppearanceSettingsPane(settings: settings)
                case .advanced: advanced
                }
            }.formStyle(.grouped).navigationTitle((pane ?? .general).rawValue)
        }
        .task(id: visibility.isVisible ? pane : nil) {
            guard visibility.isVisible, pane == .general, !loginBusy else { return }
            let request = UUID(); loginStatusRequest = request
            loginStatusChecking = true
            defer { if loginStatusRequest == request { loginStatusChecking = false } }
            let status = await LoginItemWorker.status()
            guard !Task.isCancelled else { return }
            loginStatus = status
            permissions.refresh()
        }
        .onChange(of: settings.allowedWindowSubroles) { _, values in
            let draft = subrolesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if draft != values { subrolesText = values.joined(separator: ", ") }
        }
        .alert("Reset all settings?", isPresented: $resetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { reset() }
        } message: { Text("Restore default preferences. Native Dock recovery backups are preserved. Your imported pin list is kept until you re-import it.") }
        .alert("Replace pinned apps?", isPresented: $reimportConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-import", role: .destructive) { pinnedApps.reimportNativeDock() }
        } message: { Text("Replace DogBar's pinned apps with the current native Dock list.") }
        .alert("Settings action failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var general: some View {
        Group {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { setLogin($0) }))
                    .disabled(loginBusy || loginStatusChecking).settingsDescription("Start DogBar when you sign in. Status: \(loginStatusText).")
                if loginStatus == .requiresApproval {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .settingsDescription("Approve DogBar in System Settings to finish enabling login launch.")
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    .settingsDescription("Open Settings by launching DogBar again if the icon is hidden.")
            }
            Section("Permissions") {
                permissionRow("Accessibility", granted: permissions.accessibility, description: "Allows window focus, controls and keyboard shortcuts.", action: permissions.openAccessibility)
                permissionRow("Screen Recording", granted: permissions.screenRecording, description: "Allows window thumbnails. A relaunch may be needed after granting access.", action: permissions.openScreenRecording)
                Button("Show permission setup", action: onShowPermissions)
                    .settingsDescription("Open the guided permission setup window.")
                Button("Relaunch DogBar") {
                    do { try AppRelauncher.relaunch() } catch { errorMessage = error.localizedDescription }
                }.settingsDescription("Restart the installed app after permission changes, restoring the native Dock first.")
                if permissions.usesAdHocSigning {
                    Text("This build is ad-hoc signed. Rebuilds can lose permission grants. Create a DockWindow Dev code-signing certificate in Keychain Access, then rebuild.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Session") {
                Toggle("Pause DogBar", isOn: $settings.isPaused)
                    .settingsDescription("Suspend features and restore the native Dock while paused.")
                Button("Restore Native Dock", action: onRestoreNativeDock)
                    .settingsDescription("Restore the original Dock preferences through the app coordinator.")
                Button("Reset all settings", role: .destructive) { resetConfirmation = true }
                    .disabled(loginBusy || loginStatusChecking).settingsDescription("Restore defaults after confirmation, preserving native Dock recovery backups.")
            }
        }
    }
    private func permissionRow(_ title: String, granted: Bool, description: String, action: @escaping () -> Void) -> some View {
        SettingsControl(description: description) {
            HStack {
                let state = PermissionRowStatus(hasChecked: permissions.hasCheckedPermissions, granted: granted)
                Label(title + ": " + state.label, systemImage: state.symbol)
                    .foregroundStyle(state == .checking ? Color.secondary : (granted ? Color.green : Color.orange))
                Spacer()
                Button(permissions.hasCheckedPermissions ? (granted ? "Open System Settings" : "Request access") : "Checking...", action: action)
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
    private var advanced: some View {
        Group {
            Section("Private API availability") {
                ForEach(DiagnosticsService.privateAPIAvailability.keys.sorted(), id: \.self) { symbol in
                    Label(symbol, systemImage: DiagnosticsService.privateAPIAvailability[symbol] == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(DiagnosticsService.privateAPIAvailability[symbol] == true ? Color.green : Color.red)
                        .font(.system(.caption, design: .monospaced))
                }
                Text("Symbol presence enables a capability but does not guarantee every call succeeds.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Toggle("Debug logging", isOn: Binding(get: { settings.debugLogging }, set: { settings.debugLogging = $0; DiagnosticsService.setDebugLogging($0) }))
                    .settingsDescription("Write extra diagnostics to the local log file.")
                Button("Reveal log file") { DiagnosticsService.revealLogFile() }
                    .settingsDescription("Show \(DiagnosticsService.logFileURL.path) in Finder.")
                TextField("Allowed window subroles", text: $subrolesText)
                    .onAppear { subrolesText = settings.allowedWindowSubroles.joined(separator: ", ") }
                    .onChange(of: subrolesText) { _, text in
                        settings.allowedWindowSubroles = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }.settingsDescription("Comma-separated AX subroles, normally AXStandardWindow and AXDialog.")
                Button("Re-import pinned apps from native Dock") { reimportConfirmation = true }
                    .settingsDescription("Replace DogBar's pins after confirmation. The native Dock is unchanged.")
            }
        }
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
