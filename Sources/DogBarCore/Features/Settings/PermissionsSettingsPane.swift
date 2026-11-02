import SwiftUI

/// The two permissions DogBar needs, and the ways back when one goes missing.
@MainActor struct PermissionsSettingsPane: View {
    @ObservedObject var permissions: PermissionsService
    @ObservedObject var visibility: SettingsVisibility
    let onShowPermissions: () -> Void
    @State private var errorMessage: String?

    var body: some View {
        Group {
            SettingsSection("Required", footer: "DogBar never reads what you type, and window images never leave your Mac.") {
                permissionRow("Accessibility", granted: permissions.accessibility,
                              description: "Focus, close and minimize single windows, and use shortcuts.", action: permissions.openAccessibility)
                    .settingsAnchor("general.accessibility")
                permissionRow("Screen Recording", granted: permissions.screenRecording,
                              description: "Real window thumbnails. May need a relaunch after allowing.", action: permissions.openScreenRecording)
                    .settingsAnchor("general.screenrecording")
            }
            SettingsSection("Troubleshooting") {
                SettingsRow("Guided setup", description: "Walk through permissions again.") {
                    Button("Show Setup", action: onShowPermissions)
                }
                .settingsAnchor("general.setup")
                SettingsRow("Relaunch", description: "After permission changes. Apple’s Dock is restored first.") {
                    Button("Relaunch DogBar") {
                        do { try AppRelauncher.relaunch() } catch { errorMessage = error.localizedDescription }
                    }
                }
                .settingsAnchor("general.relaunch")
                if permissions.usesAdHocSigning {
                    SettingsDescriptionText("This build is ad-hoc signed, so rebuilds can lose permissions. Create a DockWindow Dev code-signing certificate in Keychain Access, then rebuild.")
                }
            }
        }
        // Recheck when Settings becomes visible; the General page does the same.
        .task(id: visibility.isVisible) { if visibility.isVisible { permissions.refresh() } }
        .alert("Settings action failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func permissionRow(_ title: String, granted: Bool, description: String, action: @escaping () -> Void) -> some View {
        let state = PermissionRowStatus(hasChecked: permissions.hasCheckedPermissions, granted: granted)
        return SettingsRow(title, description: description) {
            HStack(spacing: 10) {
                SettingsStatusPill(text: state.label, symbol: state == .checking ? nil : state.symbol,
                                   tone: state == .checking ? .neutral : granted ? .good : .warning)
                Group {
                    if state == .missing {
                        Button("Allow…", action: action).buttonStyle(.borderedProminent)
                    } else {
                        Button("Open Settings", action: action)
                    }
                }
                .disabled(!permissions.hasCheckedPermissions || permissions.isChecking)
            }
        }
    }
}
