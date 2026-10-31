import SwiftUI

@MainActor struct SwitcherSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Group {
            SettingsSection("Activation") {
                Picker("Switcher", selection: $settings.switcherMode) {
                    Text("Windows").tag(SwitcherMode.windows)
                    Text("Apps").tag(SwitcherMode.apps)
                    Text("macOS default").tag(SwitcherMode.native)
                }.pickerStyle(.segmented)
                Text(modeDescription).font(.callout).foregroundStyle(.secondary)
            }
            if settings.switcherMode != .native {
            SettingsSection("Shortcuts") {
                HStack { Text("Shortcut"); Spacer(); ShortcutRecorder(shortcut: $settings.switcherShortcut) }.settingsDescription("Click to record a modifier and physical key. Default: Option+Tab. Esc cancels.")
                Toggle("Enable same-app shortcut", isOn: $settings.sameAppShortcutEnabled).settingsDescription("Switch only between windows belonging to the active app.")
                HStack { Text("Same-app shortcut"); Spacer(); ShortcutRecorder(shortcut: $settings.sameAppShortcut) }.disabled(!settings.sameAppShortcutEnabled).settingsDescription("Record the same-app shortcut. Default: Command+grave accent.")
            }
            if settings.switcherMode == .windows {
            SettingsSection("Windows") {
                SettingsChoice(title: "Windows from", description: "Choose current-desktop windows or windows across desktops.", value: $settings.switcherScope)
                SettingsChoice(title: "Screens", description: "Include every display or only the display under the pointer.", value: $settings.switcherScreens, choices: [.all, .withMouse])
                Toggle("Include minimized", isOn: $settings.switcherIncludeMinimized).settingsDescription("Show minimized windows and restore them when selected.")
                Toggle("Include hidden apps", isOn: $settings.switcherIncludeHiddenApps).settingsDescription("Show windows belonging to hidden applications.")
                Toggle("Show windowless apps", isOn: $settings.switcherShowWindowlessApps).settingsDescription("Include running apps that have no eligible windows.")
            }
            }
            if settings.switcherMode == .apps {
                SettingsSection("Applications") {
                    Toggle("Include hidden apps", isOn: $settings.switcherIncludeHiddenApps)
                        .settingsDescription("Show one icon per running app across all desktops, including apps with no open windows.")
                }
            }
            SettingsSection("Layout") {
                SettingsSlider(title: "Appearance delay", description: "Allow quick switching before showing the panel.", value: $settings.switcherAppearanceDelay, range: 0...1, step: 0.01, unit: "s")
                if settings.switcherMode == .windows {
                SettingsSlider(title: "Thumbnail width", description: "Set the width of each window thumbnail.", value: $settings.switcherThumbnailWidth, range: 160...600, step: 1, unit: "pt")
                SettingsSlider(title: "Thumbnail height", description: "Set the height of each window thumbnail.", value: $settings.switcherThumbnailHeight, range: 100...400, step: 1, unit: "pt")
                }
                Stepper("Maximum tiles per row: \(settings.switcherMaxTilesPerRow)", value: $settings.switcherMaxTilesPerRow, in: 1...10).settingsDescription("Wrap additional windows onto another row.")
            }
            SettingsSection("Keyboard actions") {
                if settings.switcherMode == .windows {
                Toggle("W closes window", isOn: $settings.switcherCloseWithW).settingsDescription("Press W while switching to close the selected window.")
                Toggle("M minimizes window", isOn: $settings.switcherMinimizeWithM).settingsDescription("Press M while switching to minimize the selected window.")
                }
                Toggle("H hides app", isOn: $settings.switcherHideWithH).settingsDescription("Press H while switching to hide the selected application.")
                Toggle("Q quits app", isOn: $settings.switcherQuitWithQ).settingsDescription("Press Q while switching to quit the selected application.")
            }
            }
        }
    }
    private var modeDescription: String {
        switch settings.switcherMode {
        case .windows: return "One preview per window. Release the shortcut to go straight to the selected window."
        case .apps: return "One icon per running app, like macOS. Selecting an app brings its windows forward. The same-app shortcut still switches windows."
        case .native: return "Use Apple's built-in Cmd+Tab and same-app switching. DogBar leaves these shortcuts alone; Dock features stay available."
        }
    }
}
