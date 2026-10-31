import SwiftUI

@MainActor struct SwitcherSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Group {
            Section("Activation") {
                Toggle("Enable window switcher", isOn: $settings.switcherEnabled).settingsDescription("Use DogBar to switch between individual windows.")
                HStack { Text("Shortcut"); Spacer(); ShortcutRecorder(shortcut: $settings.switcherShortcut) }.settingsDescription("Click to record a modifier and physical key. Default: Option+Tab. Esc cancels.")
                Toggle("Enable same-app shortcut", isOn: $settings.sameAppShortcutEnabled).settingsDescription("Switch only between windows belonging to the active app.")
                HStack { Text("Same-app shortcut"); Spacer(); ShortcutRecorder(shortcut: $settings.sameAppShortcut) }.disabled(!settings.sameAppShortcutEnabled).settingsDescription("Record the same-app shortcut. Default: Command+grave accent.")
            }
            Section("Windows") {
                SettingsChoice(title: "Windows from", description: "Choose current-desktop windows or windows across desktops.", value: $settings.switcherScope)
                SettingsChoice(title: "Screens", description: "Include every display or only the display under the pointer.", value: $settings.switcherScreens, choices: [.all, .withMouse])
                Toggle("Include minimized", isOn: $settings.switcherIncludeMinimized).settingsDescription("Show minimized windows and restore them when selected.")
                Toggle("Include hidden apps", isOn: $settings.switcherIncludeHiddenApps).settingsDescription("Show windows belonging to hidden applications.")
                Toggle("Show windowless apps", isOn: $settings.switcherShowWindowlessApps).settingsDescription("Include running apps that have no eligible windows.")
            }
            Section("Layout") {
                SettingsSlider(title: "Appearance delay", description: "Allow quick switching before showing the panel.", value: $settings.switcherAppearanceDelay, range: 0...1, step: 0.01, unit: "s")
                SettingsSlider(title: "Thumbnail width", description: "Set the width of each window thumbnail.", value: $settings.switcherThumbnailWidth, range: 160...600, step: 1, unit: "pt")
                SettingsSlider(title: "Thumbnail height", description: "Set the height of each window thumbnail.", value: $settings.switcherThumbnailHeight, range: 100...400, step: 1, unit: "pt")
                Stepper("Maximum tiles per row: \(settings.switcherMaxTilesPerRow)", value: $settings.switcherMaxTilesPerRow, in: 1...10).settingsDescription("Wrap additional windows onto another row.")
            }
            Section("Keyboard actions") {
                Toggle("W closes window", isOn: $settings.switcherCloseWithW).settingsDescription("Press W while switching to close the selected window.")
                Toggle("M minimizes window", isOn: $settings.switcherMinimizeWithM).settingsDescription("Press M while switching to minimize the selected window.")
                Toggle("H hides app", isOn: $settings.switcherHideWithH).settingsDescription("Press H while switching to hide the selected application.")
                Toggle("Q quits app", isOn: $settings.switcherQuitWithQ).settingsDescription("Press Q while switching to quit the selected application.")
            }
        }
    }
}
