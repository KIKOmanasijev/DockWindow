import AppKit
import Combine
import ServiceManagement
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", dock = "Dock", switcher = "Switcher", previews = "Dock Previews", appearance = "Appearance", advanced = "Advanced"
    var id: String { rawValue }
    var detail: String {
        switch self {
        case .general: return "Startup, permissions and your DogBar session."
        case .dock: return "Choose what appears in your Dock and how it behaves."
        case .switcher: return "Switch between windows, apps, or use the macOS default."
        case .previews: return "Make window previews work the way you do."
        case .appearance: return "Adjust the appearance of your Dock and panels."
        case .advanced: return "Diagnostics and advanced configuration."
        }
    }
    var searchTerms: String {
        switch self {
        case .general: return "startup login permissions accessibility screen recording pause reset menu bar"
        case .dock: return "icons size resize hide pinned recent trash desktop windows magnification click scroll"
        case .switcher: return "shortcut keyboard alt tab option command apps windows native minimized hidden thumbnails"
        case .previews: return "hover delay preview cpu ram memory new window performance"
        case .appearance: return "theme light dark color material opacity animation motion corners"
        case .advanced: return "debug logs private api subroles import pinned diagnostics"
        }
    }
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
    @State private var search = ""
    @State private var resetConfirmation = false
    @State private var reimportConfirmation = false
    @State private var errorMessage: String?
    @State private var loginStatus = SMAppService.Status.notRegistered
    @State private var loginStatusChecking = true
    @State private var loginStatusRequest = UUID()
    @State private var loginBusy = false
    @State private var subrolesText = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text((pane ?? .general).rawValue).font(.system(size: 24, weight: .semibold))
                    Text((pane ?? .general).detail).font(.callout).foregroundStyle(.secondary)
                }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 8)
                Form {
                    switch pane ?? .general {
                    case .general: general
                    case .dock: DockSettingsPane(settings: settings)
                    case .switcher: SwitcherSettingsPane(settings: settings)
                    case .previews: PreviewSettingsPane(settings: settings)
                    case .appearance: AppearanceSettingsPane(settings: settings)
                    case .advanced: advanced
                    }
                }.formStyle(.grouped).scrollContentBackground(.hidden)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DogBar").font(.system(size: 17, weight: .semibold))
                    Text("Settings").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 12).padding(.top, 18)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a section", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(9).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SettingsPane.allCases.filter { search.isEmpty || ($0.rawValue + " " + $0.searchTerms).localizedCaseInsensitiveContains(search) }) { item in
                        Button { pane = item } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.symbol).font(.system(size: 15, weight: .medium))
                                    .frame(width: 28, height: 28)
                                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                                Text(item.rawValue).font(.system(size: 13, weight: pane == item ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                                .background(pane == item ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(pane == item ? .isSelected : [])
                    }
                    if !search.isEmpty && !SettingsPane.allCases.contains(where: { ($0.rawValue + " " + $0.searchTerms).localizedCaseInsensitiveContains(search) }) {
                        Text("No matching sections").font(.callout).foregroundStyle(.secondary).padding(.top, 12)
                    }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            Text("DogBar \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 20).padding(.bottom, 18)
        }.frame(width: 218).background(.regularMaterial)
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
