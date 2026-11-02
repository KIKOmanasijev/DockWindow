import SwiftUI

/// Every DogBar feature on one page: Dock & Desktops, Previews and Switcher. Each subsection
/// opens with a small demo, a one-line explanation and its main switch, then its options. Rare
/// options sit behind "More options"; search opens them.
@MainActor struct FeaturesSettingsPane: View {
    @ObservedObject var settings: AppSettings
    let pinnedApps: PinnedAppsStore
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var visibility: SettingsVisibility
    let outline: SettingsOutline
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Demos at least mostly in view. Only the topmost of them may play.
    @State private var scenesInView: Set<FeatureSection> = []
    @State private var tops = SectionTops()

    private var reduceMotion: Bool { systemReduceMotion || settings.reduceAnimations }
    private func isActive(_ section: FeatureSection) -> Bool {
        navigation.pane == .features && visibility.isVisible
            && FeatureSection.allCases.first(where: scenesInView.contains) == section
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 52) {
            dockSection.tracked(.dock, tops: tops)
            previewsSection.tracked(.previews, tops: tops)
            switcherSection.tracked(.switcher, tops: tops)
        }
        .coordinateSpace(.named(SectionTops.space))
        // Marks the subsection under the top of the page in the sidebar. The transform runs while
        // scrolling; the action only when the rounded viewport changes.
        .onGeometryChange(for: SectionTops.Viewport.self) { proxy in
            let bounds = proxy.bounds(of: .scrollView) ?? .zero
            return .init(top: (bounds.minY / 4).rounded() * 4, bottom: (bounds.maxY / 4).rounded() * 4, height: (proxy.size.height / 4).rounded() * 4)
        } action: { viewport in
            let section = tops.section(in: viewport)
            outline.track(section)
        }
    }

    private func sceneVisibility(_ section: FeatureSection) -> (Bool) -> Void {
        { visible in
            if visible { scenesInView.insert(section) } else { scenesInView.remove(section) }
        }
    }

    // MARK: Dock & Desktops

    private var dockSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHero(title: FeatureSection.dock.title,
                         text: "Every desktop gets its own Dock, with only the apps open there.") {
                DockDemoScene(enabled: settings.useDogBarDock, scope: settings.dockScope, otherApps: settings.otherDesktopApps,
                              singleDot: settings.indicatorStyle == .single, showTrash: settings.showTrash,
                              active: isActive(.dock), session: visibility.session, reduceMotion: reduceMotion)
                    .onScrollVisibilityChange(threshold: 0.7, sceneVisibility(.dock))
            } control: {
                Toggle("Use DogBar’s Dock", isOn: $settings.useDogBarDock)
                    .settingsDescription(settings.useDogBarDock ? "Replaces Apple’s Dock while DogBar runs."
                                         : "Apple’s Dock is in use. Previews and the switcher still work.")
                    .settingsAnchor("dock.enabled")
            }
            SettingsSection("Apps in each Dock") {
                SettingsChoice(title: "Desktops", description: "Desktops are macOS Spaces.",
                               value: $settings.dockScope, labels: [.currentDesktop: "This desktop only", .allDesktops: "All desktops"])
                    .settingsAnchor("dock.desktops")
                SettingsChoice(title: "Displays", description: "Which monitors’ windows count.",
                               value: $settings.dockDisplayScope, labels: [.allDisplays: "All displays", .currentDisplay: "The Dock’s display"])
                    .settingsAnchor("dock.displays")
                SettingsChoice(title: "Apps open on other desktops", description: "Leave them out, or list them dimmed at the end.",
                               value: $settings.otherDesktopApps, labels: [.hidden: "Hide", .dimmed: "Show dimmed"])
                    .disabled(settings.dockScope == .allDesktops)
                    .settingsAnchor("dock.otherDesktops")
                Toggle("Hide apps with no open windows", isOn: $settings.hideWindowlessApps)
                    .settingsDescription("Pinned apps always stay.")
                    .settingsAnchor("dock.windowless")
                PinnedAppsRow(pinnedApps: pinnedApps)
                SettingsMore("dock.apps.more") {
                    Toggle("Include minimized windows", isOn: $settings.includeMinimizedInDock)
                        .settingsDescription("Keep an app in this desktop’s Dock while its windows here are minimized.")
                        .settingsAnchor("dock.minimized")
                    Toggle("Keep windowless apps on their last desktop", isOn: $settings.showWindowlessAppsOnLastActiveDesktop)
                        .settingsDescription("A running app with no windows stays where you last used it.")
                        .disabled(settings.hideWindowlessApps)
                        .settingsAnchor("dock.lastDesktop")
                }
            }
            .disabled(!settings.useDogBarDock)
            SettingsSection("Layout") {
                SettingsChoice(title: "Position", description: nil, value: $settings.dockPosition)
                    .settingsAnchor("dock.position")
                SettingsChoice(title: "Display", description: "Push the pointer at another display’s edge to move the Dock there.",
                               value: $settings.dockDisplay, choices: [.pushToMove, .main, .withMouse],
                               labels: [.pushToMove: "Push at an edge to move", .main: "Main display", .withMouse: "Follow the pointer"])
                    .settingsAnchor("dock.display")
                SettingsSlider(title: "Icon size", description: nil, value: $settings.iconSize, range: 16...128, step: 1, unit: "pt")
                    .settingsAnchor("dock.iconSize")
                Toggle("Automatically hide the Dock", isOn: $settings.autohide)
                    .settingsDescription("It comes back when the pointer reaches its edge.")
                    .settingsAnchor("dock.autohide")
                if settings.autohide {
                    SettingsSlider(title: "Autohide delay", description: nil, value: $settings.autohideDelay, range: 0...3, step: 0.05, unit: "s")
                        .settingsAnchor("dock.autohideDelay")
                }
                Toggle("Keep maximized windows clear of the Dock", isOn: $settings.keepMaximizedWindowsClear)
                    .settingsDescription("Full-screen windows and a hidden Dock are unaffected.")
                    .settingsAnchor("dock.maximized")
            }
            .disabled(!settings.useDogBarDock)
            SettingsSection("Icons and window dots") {
                SettingsChoice(title: "Window dots", description: "Count each window, or one dot per running app.", value: $settings.indicatorStyle)
                    .settingsAnchor("dock.indicators")
                if settings.indicatorStyle == .perWindow {
                    SettingsRow("Maximum dots") {
                        Stepper(value: $settings.maxDots, in: 1...10) {
                            Text("\(settings.maxDots)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(SettingsPalette.muted)
                        }
                        .accessibilityLabel("Maximum dots").accessibilityValue("\(settings.maxDots)")
                    }
                    .settingsAnchor("dock.maxDots")
                }
                Toggle("Show app names on hover", isOn: $settings.showAppNameLabels)
                    .settingsAnchor("dock.labels")
                SettingsChoice(title: "Clicking the active app", description: nil,
                               value: $settings.activeAppClickBehavior,
                               labels: [.none: "Do nothing", .cycle: "Cycle its windows", .minimize: "Minimize", .hide: "Hide"])
                    .settingsAnchor("dock.click")
                Toggle("Scroll to cycle windows", isOn: $settings.scrollToCycleWindows)
                    .settingsDescription("Scroll over an icon to move between its windows.")
                    .settingsAnchor("dock.scroll")
                Toggle("Bounce apps while they open", isOn: $settings.bounceOnLaunch)
                    .settingsAnchor("dock.bounce")
                Toggle("Show Trash", isOn: $settings.showTrash)
                    .settingsAnchor("dock.trash")
                SettingsMore("dock.indicators.more") {
                    Toggle("Count minimized windows", isOn: $settings.includeMinimizedInCount)
                        .settingsDescription("Include minimized windows in the dots.")
                        .settingsAnchor("dock.countMinimized")
                    Toggle("Mark running apps without windows", isOn: $settings.showRunningState)
                        .settingsDescription("A hollow ring under the icon.")
                        .settingsAnchor("dock.runningState")
                    Toggle("Custom dot color", isOn: $settings.useCustomDotColor)
                        .settingsDescription("Instead of the system color.")
                        .settingsAnchor("dock.dotColor")
                    SettingsColorPicker(title: "Dot color", description: nil, value: $settings.dotColor)
                        .disabled(!settings.useCustomDotColor)
                }
            }
            .disabled(!settings.useDogBarDock)
        }
    }

    // MARK: Previews

    private var previewsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHero(title: FeatureSection.previews.title,
                         text: "Hover an app in the Dock to see its windows. Click one to bring just that window forward.") {
                PreviewsDemoScene(enabled: settings.previewsEnabled, hoverDelay: settings.previewHoverDelay,
                                  showTitles: settings.previewShowWindowTitles, showNewWindowTile: settings.previewShowNewWindowTile,
                                  showCPU: settings.previewShowCPUUsage, showMemory: settings.previewShowMemoryUsage,
                                  active: isActive(.previews), session: visibility.session, reduceMotion: reduceMotion)
                    .onScrollVisibilityChange(threshold: 0.7, sceneVisibility(.previews))
            } control: {
                Toggle("Dock previews", isOn: $settings.previewsEnabled)
                    .settingsDescription("Work with DogBar’s Dock and Apple’s.")
                    .settingsAnchor("previews.enabled")
            }
            SettingsSection("Previews") {
                SettingsSlider(title: "Hover delay", description: "How long to rest on an icon first.",
                               value: $settings.previewHoverDelay, range: 0...1, step: 0.01, unit: "s")
                    .settingsAnchor("previews.delay")
                SettingsChoice(title: "Show windows from", description: nil, value: $settings.previewScope,
                               labels: [.currentDesktop: "This desktop", .allDesktops: "All desktops"])
                    .settingsAnchor("previews.scope")
                SettingsSlider(title: "Thumbnail height", description: nil, value: $settings.previewThumbnailHeight, range: 80...400, step: 1, unit: "pt")
                    .settingsAnchor("previews.height")
                Toggle("Show window titles", isOn: $settings.previewShowWindowTitles)
                    .settingsAnchor("previews.titles")
                Toggle("Show window controls", isOn: $settings.previewShowTrafficLights)
                    .settingsDescription("Close, minimize and full screen on each preview.")
                    .settingsAnchor("previews.trafficLights")
                Toggle("Show New Window tile", isOn: $settings.previewShowNewWindowTile)
                    .settingsDescription("A + after an app’s windows. Per-app rules are in Advanced.")
                    .settingsAnchor("previews.newWindow")
                Toggle("Include minimized windows", isOn: $settings.previewIncludeMinimized)
                    .settingsAnchor("previews.minimized")
                SettingsMore("previews.more") {
                    Toggle("Previews for apps without windows", isOn: $settings.previewShowEmptyApps)
                        .settingsDescription("Shows a New Window button instead.")
                        .settingsAnchor("previews.empty")
                    Toggle("Show app CPU usage", isOn: $settings.previewShowCPUUsage)
                        .settingsDescription("The app and its helpers. 100% is one core.")
                        .settingsAnchor("previews.cpu")
                    Toggle("Show app memory usage", isOn: $settings.previewShowMemoryUsage)
                        .settingsDescription("The app and its helpers. Shared memory may count twice.")
                        .settingsAnchor("previews.ram")
                    Toggle("Point at the Dock icon", isOn: $settings.previewShowPointer)
                        .settingsDescription("An arrow on the preview points to its icon.")
                        .settingsAnchor("previews.pointer")
                    SettingsSlider(title: "Live refresh", description: "How often open thumbnails update.",
                                   value: $settings.thumbnailRefreshInterval, range: 0...10, step: 0.25, unit: "s", zeroLabel: "Off")
                        .settingsAnchor("previews.refresh")
                }
            }
            .disabled(!settings.previewsEnabled)
        }
    }

    // MARK: Switcher

    private var switcherSection: some View {
        let mode = settings.switcherMode
        return VStack(alignment: .leading, spacing: 24) {
            SettingsHero(title: FeatureSection.switcher.title, text: switcherText) {
                SwitcherDemoScene(mode: mode, shortcut: settings.switcherShortcut, appearanceDelay: settings.switcherAppearanceDelay,
                                  selectionColor: Theme.selection(settings),
                                  active: isActive(.switcher), session: visibility.session, reduceMotion: reduceMotion)
                    .onScrollVisibilityChange(threshold: 0.7, sceneVisibility(.switcher))
            } control: {
                SettingsRow("Switch between", description: mode == .native ? "DogBar’s Dock and previews keep working." : nil) {
                    Picker("Switcher mode", selection: $settings.switcherMode) {
                        Text("Windows").tag(SwitcherMode.windows)
                        Text("Apps").tag(SwitcherMode.apps)
                        Text("macOS").tag(SwitcherMode.native)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .accessibilityLabel("Switcher mode")
                }
                .settingsAnchor("switcher.mode")
            }
            if mode != .native {
                SettingsSection("Shortcuts") {
                    SettingsRow("Switcher", description: "Click, then press the keys. Esc cancels.") {
                        ShortcutRecorder(shortcut: $settings.switcherShortcut)
                    }
                    .settingsAnchor("switcher.shortcut")
                    Toggle("Same-app shortcut", isOn: $settings.sameAppShortcutEnabled)
                        .settingsDescription("Switch only between the active app’s windows.")
                        .settingsAnchor("switcher.sameApp")
                    SettingsRow("Same-app keys") { ShortcutRecorder(shortcut: $settings.sameAppShortcut) }
                        .disabled(!settings.sameAppShortcutEnabled)
                }
                if mode == .windows {
                    SettingsSection("Windows") {
                        SettingsChoice(title: "Desktops", description: nil,
                                       value: $settings.switcherScope, labels: [.currentDesktop: "This desktop", .allDesktops: "All desktops"])
                            .settingsAnchor("switcher.scope")
                        SettingsChoice(title: "Displays", description: nil,
                                       value: $settings.switcherScreens, choices: [.all, .withMouse],
                                       labels: [.all: "All displays", .withMouse: "Display with the pointer"])
                            .settingsAnchor("switcher.screens")
                        Toggle("Include minimized windows", isOn: $settings.switcherIncludeMinimized)
                            .settingsDescription("Choosing one restores it.")
                            .settingsAnchor("switcher.minimized")
                        Toggle("Include hidden apps", isOn: $settings.switcherIncludeHiddenApps)
                            .settingsAnchor("switcher.hidden")
                        Toggle("Show apps without windows", isOn: $settings.switcherShowWindowlessApps)
                            .settingsAnchor("switcher.windowless")
                    }
                } else {
                    SettingsSection("Apps") {
                        Toggle("Include hidden apps", isOn: $settings.switcherIncludeHiddenApps)
                            .settingsDescription("Apps mode lists every running app, with or without windows.")
                            .settingsAnchor("switcher.hidden")
                    }
                }
                SettingsSection("Panel") {
                    SettingsSlider(title: "Appearance delay", description: "Quick taps switch without showing the panel.",
                                   value: $settings.switcherAppearanceDelay, range: 0...1, step: 0.01, unit: "s")
                        .settingsAnchor("switcher.delay")
                    SwitcherKeyActions(settings: settings, windows: mode == .windows)
                        .settingsAnchor("switcher.keys")
                    SettingsMore("switcher.more") {
                        if mode == .windows {
                            SettingsSlider(title: "Thumbnail width", description: nil,
                                           value: $settings.switcherThumbnailWidth, range: 160...600, step: 1, unit: "pt")
                                .settingsAnchor("switcher.thumbnails")
                            SettingsSlider(title: "Thumbnail height", description: nil,
                                           value: $settings.switcherThumbnailHeight, range: 100...400, step: 1, unit: "pt")
                        }
                        SettingsRow("Maximum tiles per row", description: "More tiles wrap onto another row.") {
                            Stepper(value: $settings.switcherMaxTilesPerRow, in: 1...10) {
                                Text("\(settings.switcherMaxTilesPerRow)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(SettingsPalette.muted)
                            }
                            .accessibilityLabel("Maximum tiles per row").accessibilityValue("\(settings.switcherMaxTilesPerRow)")
                        }
                        .settingsAnchor("switcher.tilesPerRow")
                    }
                }
            }
        }
    }

    private var switcherText: String {
        switch settings.switcherMode {
        case .windows: return "Hold the shortcut and tap to pick any window. Let go to jump straight to it."
        case .apps: return "One icon per app, like macOS. The same-app shortcut still picks windows."
        case .native: return "Apple’s ⌘Tab is in charge. DogBar’s switcher is off."
        }
    }
}

/// W, M, H and Q: keys that act on the selection while the switcher is open, as checkboxes.
private struct SwitcherKeyActions: View {
    @ObservedObject var settings: AppSettings
    let windows: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRowText(title: Text("Keys while switching"), description: "Press one while the panel is open.")
            HStack(spacing: 18) {
                if windows {
                    action("W", "Close window", $settings.switcherCloseWithW)
                    action("M", "Minimize", $settings.switcherMinimizeWithM)
                }
                action("H", "Hide app", $settings.switcherHideWithH)
                action("Q", "Quit app", $settings.switcherQuitWithQ)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func action(_ key: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 5) {
                Text(title)
                Text(key).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("\(key) to \(title.lowercased())")
    }
}

/// Pins belong to a desktop. Copying replaces only the current desktop's pins.
private struct PinnedAppsRow: View {
    @ObservedObject var pinnedApps: PinnedAppsStore
    @State private var confirmation = false
    @State private var desktopKey: String?
    var body: some View {
        SettingsRow("Pinned apps", description: "Each desktop keeps its own pins and order.") {
            Button("Copy from Apple’s Dock…") { desktopKey = pinnedApps.activeDesktopKey; confirmation = true }
                .disabled(!pinnedApps.canEdit)
        }
        .settingsAnchor("dock.pins")
        .onChange(of: pinnedApps.activeDesktopKey) { _, _ in confirmation = false }
        .alert("Replace this desktop’s pins?", isPresented: $confirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                if pinnedApps.activeDesktopKey == desktopKey { pinnedApps.reimportNativeDock() }
            }
        } message: { Text("This desktop’s pinned apps become the ones in Apple’s Dock. Other desktops are unchanged.") }
    }
}

/// Section tops in page coordinates, measured on layout (not while scrolling), and the rule that
/// picks the subsection under the top of the visible page.
@MainActor final class SectionTops {
    nonisolated static let space = "settings.features.page"
    struct Viewport: Equatable { var top: CGFloat; var bottom: CGFloat; var height: CGFloat }
    var values: [FeatureSection: CGFloat] = [:]
    func section(in viewport: Viewport) -> FeatureSection {
        let probe = viewport.top + 120
        var current = FeatureSection.dock
        for section in FeatureSection.allCases where (values[section] ?? .infinity) <= probe { current = section }
        // At the bottom, a last subsection whose top is in view counts even if it is short.
        if viewport.bottom >= viewport.height - 8, let last = FeatureSection.allCases.last,
           let top = values[last], top >= viewport.top { current = last }
        return current
    }
}

private extension View {
    func tracked(_ section: FeatureSection, tops: SectionTops) -> some View {
        id(section.anchor)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(SectionTops.space)).minY } action: { tops.values[section] = $0 }
    }
}
