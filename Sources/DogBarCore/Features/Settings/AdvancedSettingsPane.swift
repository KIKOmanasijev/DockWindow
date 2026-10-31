import SwiftUI

@MainActor struct AdvancedSettingsPane: View {
    @ObservedObject var settings: AppSettings
    let pinnedApps: PinnedAppsStore
    @State private var reimportConfirmation = false
    @State private var subrolesText = ""

    var body: some View {
        Group {
            SettingsSection("Private API availability") {
                ForEach(DiagnosticsService.privateAPIAvailability.keys.sorted(), id: \.self) { symbol in
                    Label(symbol, systemImage: DiagnosticsService.privateAPIAvailability[symbol] == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(DiagnosticsService.privateAPIAvailability[symbol] == true ? Color.green : Color.red)
                        .font(.system(.caption, design: .monospaced))
                }
                Text("Symbol presence enables a capability but does not guarantee every call succeeds.").font(.caption).foregroundStyle(.secondary)
            }
            SettingsSection("Diagnostics") {
                Toggle("Debug logging", isOn: Binding(get: { settings.debugLogging }, set: { settings.debugLogging = $0; DiagnosticsService.setDebugLogging($0) }))
                    .settingsDescription("Write extra diagnostics to the local log file.")
                SettingsRow("Log file", description: DiagnosticsService.logFileURL.path) {
                    Button("Reveal in Finder") { DiagnosticsService.revealLogFile() }
                }
                TextField("Allowed window subroles", text: $subrolesText)
                    .onAppear { subrolesText = settings.allowedWindowSubroles.joined(separator: ", ") }
                    .onChange(of: subrolesText) { _, text in
                        let values = Self.subroles(text)
                        if settings.allowedWindowSubroles != values { settings.allowedWindowSubroles = values }
                    }.settingsDescription("Comma-separated AX subroles, normally AXStandardWindow and AXDialog.")
                SettingsRow("Pinned apps", description: "Replace DogBar's pins after confirmation. The native Dock is unchanged.") {
                    Button("Re-import from Native Dock…") { reimportConfirmation = true }
                }
            }
        }
        .onChange(of: settings.allowedWindowSubroles) { _, values in
            if Self.subroles(subrolesText) != values { subrolesText = values.joined(separator: ", ") }
        }
        .alert("Replace pinned apps?", isPresented: $reimportConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-import", role: .destructive) { pinnedApps.reimportNativeDock() }
        } message: { Text("Replace DogBar's pinned apps with the current native Dock list.") }
    }
    private static func subroles(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
