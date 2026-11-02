import SwiftUI

@MainActor struct AdvancedSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @State private var subrolesText = ""

    var body: some View {
        Group {
            SettingsSection("New window rules", footer: "How DogBar opens another window for an app, from previews, the Dock menu and the switcher. Automatic tries the menu, then the shortcut, then reopening the app.") {
                NewWindowRulesEditor(settings: settings)
            }
            .settingsAnchor("advanced.rules")
            SettingsSection("Diagnostics") {
                Toggle("Debug logging", isOn: Binding(get: { settings.debugLogging }, set: { settings.debugLogging = $0; DiagnosticsService.setDebugLogging($0) }))
                    .settingsDescription("Write extra diagnostics to the local log file.")
                    .settingsAnchor("advanced.debug")
                SettingsRow("Log file", description: DiagnosticsService.logFileURL.path) {
                    Button("Reveal in Finder") { DiagnosticsService.revealLogFile() }
                }
                .settingsAnchor("advanced.log")
                SettingsMore("advanced.api.more", title: "Private API availability") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(DiagnosticsService.privateAPIAvailability.keys.sorted(), id: \.self) { symbol in
                            let available = DiagnosticsService.privateAPIAvailability[symbol] == true
                            Label(symbol, systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(available ? SettingsPalette.success : Color.red)
                                .font(.system(.caption, design: .monospaced))
                        }
                        SettingsDescriptionText("Symbol presence enables a capability but does not guarantee every call succeeds.")
                    }
                    .settingsAnchor("advanced.privateAPI")
                }
            }
            SettingsSection("Window detection") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allowed window subroles")
                    TextField("AXStandardWindow, AXDialog", text: $subrolesText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Allowed window subroles")
                        .onAppear { subrolesText = settings.allowedWindowSubroles.joined(separator: ", ") }
                        .onChange(of: subrolesText) { _, text in
                            let values = Self.subroles(text)
                            if settings.allowedWindowSubroles != values { settings.allowedWindowSubroles = values }
                        }
                    SettingsDescriptionText("Comma-separated accessibility subroles DogBar treats as windows. Normally AXStandardWindow and AXDialog.")
                }
                .settingsAnchor("advanced.subroles")
            }
        }
        .onChange(of: settings.allowedWindowSubroles) { _, values in
            if Self.subroles(subrolesText) != values { subrolesText = values.joined(separator: ", ") }
        }
    }
    private static func subroles(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
