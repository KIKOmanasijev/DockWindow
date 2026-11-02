import SwiftUI

/// How DogBar opens another window for each app.
@MainActor struct NewWindowsSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        SettingsSection("Rules", footer: "How DogBar opens another window for an app, from previews, the Dock menu and the switcher. Automatic tries the app’s menu, then its shortcut, then reopening it.") {
            NewWindowRulesEditor(settings: settings)
        }
        .settingsAnchor("advanced.rules")
    }
}

/// Logging, private API availability and which accessibility subroles count as windows.
@MainActor struct DiagnosticsSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @State private var subrolesText = ""

    var body: some View {
        Group {
            SettingsSection("Logging") {
                Toggle("Debug logging", isOn: Binding(get: { settings.debugLogging }, set: { settings.debugLogging = $0; DiagnosticsService.setDebugLogging($0) }))
                    .settingsDescription("Write extra detail to the local log file.")
                    .settingsAnchor("advanced.debug")
                SettingsRow("Log file", description: (DiagnosticsService.logFileURL.path as NSString).abbreviatingWithTildeInPath) {
                    Button("Reveal in Finder") { DiagnosticsService.revealLogFile() }
                }
                .settingsAnchor("advanced.log")
                SettingsMore("advanced.api.more", title: "Private API availability") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(DiagnosticsService.privateAPIAvailability.keys.sorted(), id: \.self) { symbol in
                            let available = DiagnosticsService.privateAPIAvailability[symbol] == true
                            HStack(spacing: 7) {
                                Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(available ? SettingsPalette.success : Color.red)
                                Text(symbol).foregroundStyle(SettingsPalette.text)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(available ? "Available" : "Unavailable")
                        }
                        SettingsDescriptionText("A present symbol enables a capability; it doesn’t guarantee every call succeeds.").padding(.top, 2)
                    }
                    .settingsAnchor("advanced.privateAPI")
                }
            }
            SettingsSection("Window detection") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsRowText(title: Text("Allowed window subroles"), description: "Accessibility subroles DogBar treats as windows, separated by commas.")
                    TextField("AXStandardWindow, AXDialog", text: $subrolesText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .accessibilityLabel("Allowed window subroles")
                        .onAppear { subrolesText = settings.allowedWindowSubroles.joined(separator: ", ") }
                        .onChange(of: subrolesText) { _, text in
                            let values = Self.subroles(text)
                            if settings.allowedWindowSubroles != values { settings.allowedWindowSubroles = values }
                        }
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
