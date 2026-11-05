import AppKit
import SwiftUI

/// Paid builds only. Free builds never list or build this page.
@MainActor struct LicenseSettingsPane: View {
    @ObservedObject var license: LicenseManager
    @State private var key = ""
    @State private var confirmDeactivate = false
    var body: some View {
        SettingsSection("DogBar License") {
            SettingsRow("License", description: license.message) {
                Image(systemName: license.isActivated ? "checkmark.seal.fill" : "key.fill")
                    .foregroundStyle(license.isActivated ? Color.green : Color.secondary)
            }
            if let configuration = license.configuration {
                if configuration.environment == "sandbox" {
                    SettingsDescriptionText("Sandbox activation. This build does not accept live purchase licenses.")
                }
                if !license.isActivated {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("License key", text: $key).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("DogBar license key")
                            .onSubmit { activate() }
                            .disabled(license.busy)
                        HStack {
                            Button("Activate This Mac") { activate() }
                                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || license.busy)
                            if license.busy { ProgressView().controlSize(.small).accessibilityLabel("Checking license") }
                            Spacer()
                            Button(configuration.environment == "sandbox" ? "Open Sandbox Checkout…" : "Buy a License…") {
                                NSWorkspace.shared.open(configuration.purchaseURL)
                            }
                        }
                    }.padding(.vertical, 6)
                } else {
                    SettingsRow("Offline access", description: license.expiresAt.map { "Saved activation is valid until \($0.formatted(date: .abbreviated, time: .omitted)). DogBar refreshes it automatically when online." }) {
                        EmptyView()
                    }
                    SettingsRow("This Mac", description: "Deactivate before moving your license to another Mac.") {
                        Button("Deactivate…") { confirmDeactivate = true }.disabled(license.busy)
                    }
                }
                if license.canRefresh {
                    SettingsRow("Refresh activation", description: "DogBar refreshes this Mac’s activation automatically when online. A temporary outage does not cancel a saved activation.") {
                        Button("Check Now") { Task { await license.check(force: true) } }.disabled(license.busy)
                    }
                }
                SettingsRow("Activated Macs", description: "Sign in by email to remove an old Mac or recover your key.") {
                    Button("Manage License…") { NSWorkspace.shared.open(configuration.manageURL) }
                }
            }
        }
        .settingsAnchor("license.activation")
        .confirmationDialog("Deactivate this Mac?", isPresented: $confirmDeactivate) {
            Button("Deactivate", role: .destructive) { Task { await license.deactivate() } }
        } message: { Text("This Mac will need to be activated again to use a licensed release.") }
    }
    private func activate() {
        guard !license.busy, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await license.activate(key: key); if license.isActivated { key = "" } }
    }
}
