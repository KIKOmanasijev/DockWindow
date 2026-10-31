import SwiftUI

@MainActor struct AppearanceSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Group {
            SettingsSection("Appearance") {
                SettingsChoice(title: "Theme", description: "Follow macOS appearance or choose light or dark panels.", value: $settings.theme)
                Toggle("Custom selection highlight", isOn: $settings.useCustomSelectionColor).settingsDescription("Use a chosen color instead of the system accent color.")
                SettingsColorPicker(title: "Selection color", description: "Choose the selected window highlight color.", value: $settings.selectionColor).disabled(!settings.useCustomSelectionColor)
                SettingsSlider(title: "Panel corner radius", description: "Adjust the rounding of floating panel corners.", value: $settings.panelCornerRadius, range: 0...48, step: 1, unit: "pt")
                SettingsChoice(title: "Background material", description: "Choose the translucent material behind panel content.", value: $settings.panelMaterial)
                Toggle("Reduce animations", isOn: $settings.reduceAnimations).settingsDescription("Limit motion in addition to the macOS Reduce Motion preference.")
            }
        }
    }
}
