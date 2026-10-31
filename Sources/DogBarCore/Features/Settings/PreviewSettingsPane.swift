import SwiftUI

@MainActor struct PreviewSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Group {
            SettingsSection("Dock previews") {
                Toggle("Enable Dock previews", isOn: $settings.previewsEnabled).settingsDescription("Show window thumbnails when hovering either Dock.")
                SettingsSlider(title: "Hover delay", description: "Wait this long before opening a preview.", value: $settings.previewHoverDelay, range: 0...1, step: 0.01, unit: "s")
                SettingsSlider(title: "Preview height", description: "Set the height of each preview thumbnail.", value: $settings.previewThumbnailHeight, range: 80...400, step: 1, unit: "pt")
                SettingsChoice(title: "Windows from", description: "Choose which desktops contribute preview windows.", value: $settings.previewScope)
                Toggle("Show window titles", isOn: $settings.previewShowWindowTitles).settingsDescription("Display a title pill on each window card.")
                Toggle("Show New Window tile", isOn: $settings.previewShowNewWindowTile).settingsDescription("Add a + tile after an app’s open windows to request another window.")
                Toggle("Show app CPU usage", isOn: $settings.previewShowCPUUsage).settingsDescription("Show total app and identifiable helper-process CPU while previews are visible. 100% equals one CPU core.")
                Toggle("Show app RAM usage", isOn: $settings.previewShowMemoryUsage).settingsDescription("Show combined resident memory for the app and identifiable helpers, across all its windows. Shared memory may be counted more than once.")
                Toggle("Show empty-app previews", isOn: $settings.previewShowEmptyApps).settingsDescription("Show a New Window button on hover when the app has no windows in the selected scope.")
                Toggle("Show traffic lights", isOn: $settings.previewShowTrafficLights).settingsDescription("Show close, minimize and fullscreen controls on cards.")
                Toggle("Include minimized", isOn: $settings.previewIncludeMinimized).settingsDescription("Show minimized windows with their cached thumbnails.")
                Toggle("Show pointer arrow", isOn: $settings.previewShowPointer).settingsDescription("Point the preview panel toward its Dock icon.")
                SettingsSlider(title: "Live refresh interval", description: "Refresh visible thumbnails at this interval. Zero disables periodic refresh.", value: $settings.thumbnailRefreshInterval, range: 0...10, step: 0.25, unit: "s")
            }
        }
    }
}
