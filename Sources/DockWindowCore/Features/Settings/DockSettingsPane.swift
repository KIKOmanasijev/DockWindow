import SwiftUI

@MainActor struct DockSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Group {
            Section("Dock mode") {
                Toggle("Use DockWindow Dock", isOn: $settings.useDockWindowDock).settingsDescription("Replace the native Dock while enabled and not paused.")
                if !settings.useDockWindowDock { Text("Native Dock mode supports previews and the switcher. Dock layout, window dots and desktop filtering require the replacement Dock.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Layout") {
                SettingsChoice(title: "Position", description: "Place the replacement Dock on a screen edge.", value: $settings.dockPosition)
                SettingsChoice(title: "Display", description: "Choose the display that hosts the replacement Dock.", value: $settings.dockDisplay, choices: [.main, .withMouse])
                SettingsSlider(title: "Icon size", description: "Set the base size of Dock icons.", value: $settings.iconSize, range: 16...128, step: 1, unit: "pt")
                Toggle("Magnification", isOn: $settings.magnificationEnabled).settingsDescription("Enlarge icons near the pointer.")
                SettingsSlider(title: "Magnified size", description: "Set the maximum size of a magnified icon.", value: $settings.magnificationSize, range: 48...128, step: 1, unit: "pt")
                Toggle("Automatically hide Dock", isOn: $settings.autohide).settingsDescription("Reveal the Dock when the pointer reaches its screen edge.")
                SettingsSlider(title: "Autohide delay", description: "Wait this long before hiding the Dock.", value: $settings.autohideDelay, range: 0...3, step: 0.05, unit: "s")
            }.disabled(!settings.useDockWindowDock)
            Section("Desktop filtering") {
                SettingsChoice(title: "Dock shows apps from", description: "Show apps with windows in the selected desktop scope.", value: $settings.dockScope)
                SettingsChoice(title: "Apps from other desktops", description: "Hide remote apps or keep them dimmed.", value: $settings.otherDesktopApps)
                Toggle("Include minimized windows", isOn: $settings.includeMinimizedInDock).settingsDescription("Keep apps visible when their local windows are minimized.")
                Toggle("Show windowless apps on last active desktop", isOn: $settings.showWindowlessAppsOnLastActiveDesktop).settingsDescription("Keep running apps without windows on their last desktop.")
            }.disabled(!settings.useDockWindowDock)
            Section("Window indicators") {
                SettingsChoice(title: "Indicator style", description: "Count open windows or show one running dot.", value: $settings.indicatorStyle)
                Stepper("Maximum dots: \(settings.maxDots)", value: $settings.maxDots, in: 1...10).settingsDescription("Cap the number of visible window dots per app.")
                Toggle("Include minimized in count", isOn: $settings.includeMinimizedInCount).settingsDescription("Count minimized windows in the indicators.")
                Toggle("Show running state without windows", isOn: $settings.showRunningState).settingsDescription("Use a hollow ring for running apps with no windows.")
                Toggle("Custom dot color", isOn: $settings.useCustomDotColor).settingsDescription("Use a chosen color instead of the system indicator color.")
                SettingsColorPicker(title: "Dot color", description: "Choose the window indicator color.", value: $settings.dotColor).disabled(!settings.useCustomDotColor)
            }.disabled(!settings.useDockWindowDock)
            Section("Interaction") {
                Toggle("Bounce on launch", isOn: $settings.bounceOnLaunch).settingsDescription("Animate an app icon when it launches.")
                Toggle("Show app name labels", isOn: $settings.showAppNameLabels).settingsDescription("Show application names while hovering icons.")
                SettingsChoice(title: "Clicking the active app", description: "Choose the action when clicking an already active app.", value: $settings.activeAppClickBehavior)
                Toggle("Scroll to cycle windows", isOn: $settings.scrollToCycleWindows).settingsDescription("Scroll over an icon to move between its windows.")
                Toggle("Show Trash", isOn: $settings.showTrash).settingsDescription("Keep Trash at the end of the replacement Dock.")
            }.disabled(!settings.useDockWindowDock)
            Section("New window rules") {
                NewWindowRulesEditor(settings: settings)
            }
        }
    }
}
