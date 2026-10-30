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
    let pinnedApps: PinnedAppsStore
    let onRestoreNativeDock: () -> Void
    let onShowPermissions: () -> Void
    @State private var pane: SettingsPane? = .general
    @State private var resetConfirmation = false
    @State private var reimportConfirmation = false
    @State private var errorMessage: String?
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginBusy = false
    @State private var subrolesText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        .onReceive(timer) { _ in
            guard NSApp.windows.contains(where: { $0.identifier?.rawValue == "DockWindow.Settings" && $0.isVisible }) else { return }
            permissions.refresh(); loginStatus = SMAppService.mainApp.status
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
        } message: { Text("Replace DockWindow's pinned apps with the current native Dock list.") }
        .alert("Settings action failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var general: some View {
        Group {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { setLogin($0) }))
                    .disabled(loginBusy).settingsDescription("Start DockWindow when you sign in. Status: \(loginStatusText).")
                if loginStatus == .requiresApproval {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .settingsDescription("Approve DockWindow in System Settings to finish enabling login launch.")
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    .settingsDescription("Open Settings by launching DockWindow again if the icon is hidden.")
            }
            Section("Permissions") {
                permissionRow("Accessibility", granted: permissions.accessibility, description: "Allows window focus, controls and keyboard shortcuts.", action: permissions.openAccessibility)
                permissionRow("Screen Recording", granted: permissions.screenRecording, description: "Allows window thumbnails. A relaunch may be needed after granting access.", action: permissions.openScreenRecording)
                Button("Show permission setup", action: onShowPermissions)
                    .settingsDescription("Open the guided permission setup window.")
                Button("Relaunch DockWindow") {
                    do { try AppRelauncher.relaunch() } catch { errorMessage = error.localizedDescription }
                }.settingsDescription("Restart the installed app after permission changes, restoring the native Dock first.")
                if permissions.usesAdHocSigning {
                    Text("This build is ad-hoc signed. Rebuilds can lose permission grants. Create a DockWindow Dev code-signing certificate in Keychain Access, then rebuild.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Session") {
                Toggle("Pause DockWindow", isOn: $settings.isPaused)
                    .settingsDescription("Suspend features and restore the native Dock while paused.")
                Button("Restore Native Dock", action: onRestoreNativeDock)
                    .settingsDescription("Restore the original Dock preferences through the app coordinator.")
                Button("Reset all settings", role: .destructive) { resetConfirmation = true }
                    .settingsDescription("Restore defaults after confirmation, preserving native Dock recovery backups.")
            }
        }
    }
    private func permissionRow(_ title: String, granted: Bool, description: String, action: @escaping () -> Void) -> some View {
        SettingsControl(description: description) {
            HStack {
                Label(title + (granted ? ": Granted" : ": Missing"), systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? Color.green : Color.orange)
                Spacer()
                Button(granted ? "Open System Settings" : "Request access", action: action)
            }
        }
    }
    private var loginStatusText: String {
        switch loginStatus {
        case .enabled: return "Enabled"
        case .notRegistered: return "Not registered"
        case .requiresApproval: return "Requires approval"
        case .notFound: return "App service not found"
        @unknown default: return "Unknown"
        }
    }
    private func setLogin(_ enabled: Bool, completion: (() -> Void)? = nil) {
        loginBusy = true
        Task { @MainActor in
            defer { loginBusy = false; loginStatus = SMAppService.mainApp.status }
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
                loginStatus = SMAppService.mainApp.status
                let succeeded = enabled ? (loginStatus == .enabled || loginStatus == .requiresApproval) : loginStatus == .notRegistered
                guard succeeded else {
                    errorMessage = "Login launch did not reach the requested state. Status: \(loginStatusText)."
                    return
                }
                settings.launchAtLogin = enabled
                completion?()
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private func reset() {
        // Do not report a reset login preference until unregister actually succeeds.
        if SMAppService.mainApp.status == .notRegistered {
            settings.reset(); DiagnosticsService.setDebugLogging(settings.debugLogging)
        } else {
            setLogin(false) { settings.reset(); DiagnosticsService.setDebugLogging(settings.debugLogging) }
        }
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
                    .settingsDescription("Replace DockWindow's pins after confirmation. The native Dock is unchanged.")
            }
        }
    }
}
