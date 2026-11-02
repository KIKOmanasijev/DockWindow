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
        VStack(alignment: .leading, spacing: 46) {
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
            if outline.section != section { outline.section = section }
        }
    }

    private func sceneVisibility(_ section: FeatureSection) -> (Bool) -> Void {
        { visible in
            if visible { scenesInView.insert(section) } else { scenesInView.remove(section) }
        }
    }

    // MARK: Dock & Desktops

    private var dockSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureHero(section: .dock, title: "A Dock for every desktop",
                        text: "Each desktop's Dock shows the apps open there, with its own pins.") {
                DockDemoScene(enabled: settings.useDogBarDock, scope: settings.dockScope, otherApps: settings.otherDesktopApps,
                              singleDot: settings.indicatorStyle == .single, showTrash: settings.showTrash,
                              active: isActive(.dock), session: visibility.session, reduceMotion: reduceMotion)
                    .onScrollVisibilityChange(threshold: 0.7, sceneVisibility(.dock))
            } control: {
                Toggle("Use DogBar Dock", isOn: $settings.useDogBarDock).toggleStyle(.switch)
                    .settingsAnchor("dock.enabled")
                if !settings.useDogBarDock {
                    Text("Apple's Dock stays. Previews and the switcher still work.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsSection("Which apps each Dock shows") {
                SettingsChoice(title: "Desktops", description: "Desktops are macOS Spaces. “Current desktop” gives every desktop its own Dock.",
                               value: $settings.dockScope, labels: [.currentDesktop: "Current desktop only", .allDesktops: "All desktops"])
                    .settingsAnchor("dock.desktops")
                SettingsChoice(title: "Displays", description: "Displays are your monitors. Choose whose windows count, separately from desktops.",
                               value: $settings.dockDisplayScope, labels: [.allDisplays: "All displays", .currentDisplay: "The Dock's display only"])
                    .settingsAnchor("dock.displays")
                SettingsChoice(title: "Apps open on other desktops", description: "Leave them out, or list them dimmed after this desktop's apps.",
                               value: $settings.otherDesktopApps, labels: [.hidden: "Hide", .dimmed: "Show dimmed"])
                    .disabled(settings.dockScope == .allDesktops)
                    .settingsAnchor("dock.otherDesktops")
                Toggle("Hide apps with no open windows", isOn: $settings.hideWindowlessApps)
                    .settingsDescription("Running and recent apps without windows stay out. Pinned apps always stay.")
                    .settingsAnchor("dock.windowless")
                SettingsMore("dock.apps.more") {
                    Toggle("Include minimized windows", isOn: $settings.includeMinimizedInDock)
                        .settingsDescription("Keep an app in this desktop's Dock while its windows here are minimized.")
                        .settingsAnchor("dock.minimized")
                    Toggle("Keep windowless apps on their last desktop", isOn: $settings.showWindowlessAppsOnLastActiveDesktop)
                        .settingsDescription("A running app with no windows stays in the Dock of the desktop you last used it on.")
                        .disabled(settings.hideWindowlessApps)
                        .settingsAnchor("dock.lastDesktop")
                }
            }
            .disabled(!settings.useDogBarDock)
            PinnedAppsSection(pinnedApps: pinnedApps)
            SettingsSection("Layout") {
                SettingsChoice(title: "Position", description: "The screen edge for DogBar's Dock.", value: $settings.dockPosition)
                    .settingsAnchor("dock.position")
                SettingsChoice(title: "Display", description: "The monitor that holds the Dock. Like macOS, push the pointer at another display's edge to move it there.",
                               value: $settings.dockDisplay, choices: [.pushToMove, .main, .withMouse],
                               labels: [.pushToMove: "Push at an edge to move", .main: "Main display", .withMouse: "Follow the pointer"])
                    .settingsAnchor("dock.display")
                SettingsSlider(title: "Icon size", description: "The size of Dock icons.", value: $settings.iconSize, range: 16...128, step: 1, unit: "pt")
                    .settingsAnchor("dock.iconSize")
                Toggle("Automatically hide the Dock", isOn: $settings.autohide)
                    .settingsDescription("Reveal it when the pointer reaches its screen edge.")
                    .settingsAnchor("dock.autohide")
                if settings.autohide {
                    SettingsSlider(title: "Autohide delay", description: "Wait this long before the Dock hides.", value: $settings.autohideDelay, range: 0...3, step: 0.05, unit: "s")
                        .settingsAnchor("dock.autohideDelay")
                }
                Toggle("Keep maximized windows clear of the Dock", isOn: $settings.keepMaximizedWindowsClear)
                    .settingsDescription("Fit maximized windows above or beside it. Full-screen windows and a hidden Dock are unaffected.")
                    .settingsAnchor("dock.maximized")
            }
            .disabled(!settings.useDogBarDock)
            SettingsSection("Icons and window dots") {
                SettingsChoice(title: "Window dots", description: "Count each open window, or show one dot for a running app.", value: $settings.indicatorStyle)
                    .settingsAnchor("dock.indicators")
                if settings.indicatorStyle == .perWindow {
                    SettingsRow("Maximum dots", description: "Cap the dots under each icon.") {
                        Stepper(value: $settings.maxDots, in: 1...10) { Text("\(settings.maxDots)").monospacedDigit() }
                            .accessibilityLabel("Maximum dots").accessibilityValue("\(settings.maxDots)")
                    }
                    .settingsAnchor("dock.maxDots")
                }
                Toggle("Show app name labels", isOn: $settings.showAppNameLabels)
                    .settingsDescription("Show the app's name while hovering its icon.")
                    .settingsAnchor("dock.labels")
                SettingsChoice(title: "Clicking the active app", description: "What happens when you click the app you're already in.",
                               value: $settings.activeAppClickBehavior,
                               labels: [.none: "Do nothing", .cycle: "Cycle its windows", .minimize: "Minimize", .hide: "Hide"])
                    .settingsAnchor("dock.click")
                Toggle("Scroll to cycle windows", isOn: $settings.scrollToCycleWindows)
                    .settingsDescription("Scroll over an icon to move between its windows.")
                    .settingsAnchor("dock.scroll")
                Toggle("Bounce apps when they open", isOn: $settings.bounceOnLaunch)
                    .settingsDescription("An app's icon bounces until it finishes launching.")
                    .settingsAnchor("dock.bounce")
                Toggle("Show Trash", isOn: $settings.showTrash)
                    .settingsDescription("Keep Trash at the end of the Dock.")
                    .settingsAnchor("dock.trash")
                SettingsMore("dock.indicators.more") {
                    Toggle("Count minimized windows", isOn: $settings.includeMinimizedInCount)
                        .settingsDescription("Include minimized windows in the dots.")
                        .settingsAnchor("dock.countMinimized")
                    Toggle("Show running apps without windows", isOn: $settings.showRunningState)
                        .settingsDescription("A hollow ring marks a running app with no windows.")
                        .settingsAnchor("dock.runningState")
                    Toggle("Custom dot color", isOn: $settings.useCustomDotColor)
                        .settingsDescription("Use your own color instead of the system's.")
                        .settingsAnchor("dock.dotColor")
                    SettingsColorPicker(title: "Dot color", description: "The color of window dots.", value: $settings.dotColor)
                        .disabled(!settings.useCustomDotColor)
                }
            }
            .disabled(!settings.useDogBarDock)
        }
    }

    // MARK: Previews

    private var previewsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureHero(section: .previews, title: "Hover to see every window",
                        text: "Click a preview and only that window comes forward.") {
                PreviewsDemoScene(enabled: settings.previewsEnabled, hoverDelay: settings.previewHoverDelay,
                                  showTitles: settings.previewShowWindowTitles, showNewWindowTile: settings.previewShowNewWindowTile,
                                  showCPU: settings.previewShowCPUUsage, showMemory: settings.previewShowMemoryUsage,
                                  active: isActive(.previews), session: visibility.session, reduceMotion: reduceMotion)
                    .onScrollVisibilityChange(threshold: 0.7, sceneVisibility(.previews))
            } control: {
                Toggle("Dock previews", isOn: $settings.previewsEnabled).toggleStyle(.switch)
                    .settingsAnchor("previews.enabled")
                Text("Works with DogBar's Dock and Apple's.").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            SettingsSection("Previews") {
                SettingsSlider(title: "Hover delay", description: "How long to rest on an icon before its preview opens.",
                               value: $settings.previewHoverDelay, range: 0...1, step: 0.01, unit: "s")
                    .settingsAnchor("previews.delay")
                SettingsChoice(title: "Show windows from", description: "Desktops are macOS Spaces.", value: $settings.previewScope,
                               labels: [.currentDesktop: "Current desktop", .allDesktops: "All desktops"])
                    .settingsAnchor("previews.scope")
                SettingsSlider(title: "Thumbnail height", description: "The size of each window preview.",
                               value: $settings.previewThumbnailHeight, range: 80...400, step: 1, unit: "pt")
                    .settingsAnchor("previews.height")
                Toggle("Show window titles", isOn: $settings.previewShowWindowTitles)
                    .settingsDescription("A title under each preview.")
                    .settingsAnchor("previews.titles")
                Toggle("Show window controls", isOn: $settings.previewShowTrafficLights)
                    .settingsDescription("Close, minimize and full-screen buttons on each preview.")
                    .settingsAnchor("previews.trafficLights")
                Toggle("Show New Window tile", isOn: $settings.previewShowNewWindowTile)
                    .settingsDescription("A + after an app's windows opens another one. Per-app rules are in Advanced.")
                    .settingsAnchor("previews.newWindow")
                Toggle("Include minimized windows", isOn: $settings.previewIncludeMinimized)
                    .settingsDescription("Show minimized windows with their last thumbnail.")
                    .settingsAnchor("previews.minimized")
                SettingsMore("previews.more") {
                    Toggle("Previews for apps without windows", isOn: $settings.previewShowEmptyApps)
                        .settingsDescription("Hovering an app with no windows here shows a New Window button.")
                        .settingsAnchor("previews.empty")
                    Toggle("Show app CPU usage", isOn: $settings.previewShowCPUUsage)
                        .settingsDescription("The app and its helpers, while a preview is open. 100% is one core.")
                        .settingsAnchor("previews.cpu")
                    Toggle("Show app memory usage", isOn: $settings.previewShowMemoryUsage)
                        .settingsDescription("Combined memory of the app and its helpers. Shared memory may count twice.")
                        .settingsAnchor("previews.ram")
                    Toggle("Point at the Dock icon", isOn: $settings.previewShowPointer)
                        .settingsDescription("An arrow on the preview points to its icon.")
                        .settingsAnchor("previews.pointer")
                    SettingsSlider(title: "Live refresh", description: "Refresh visible thumbnails this often.",
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
        return VStack(alignment: .leading, spacing: 18) {
            FeatureHero(section: .switcher, title: "Switch windows, not apps", text: switcherText) {
                SwitcherDemoScene(mode: mode, shortcut: settings.switcherShortcut, appearanceDelay: settings.switcherAppearanceDelay,
                                  selectionColor: Theme.selection(settings),
                                  active: isActive(.switcher), session: visibility.session, reduceMotion: reduceMotion)
                    .onScrollVisibilityChange(threshold: 0.7, sceneVisibility(.switcher))
            } control: {
                Picker("Switcher", selection: $settings.switcherMode) {
                    Text("Windows").tag(SwitcherMode.windows)
                    Text("Apps").tag(SwitcherMode.apps)
                    Text("macOS").tag(SwitcherMode.native)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .accessibilityLabel("Switcher mode")
                .settingsAnchor("switcher.mode")
            }
            if mode != .native {
                SettingsSection("Shortcuts") {
                    SettingsRow("Switcher shortcut", description: "Click, then press a modifier and a key. Default ⌥Tab. Esc cancels.") {
                        ShortcutRecorder(shortcut: $settings.switcherShortcut)
                    }
                    .settingsAnchor("switcher.shortcut")
                    Toggle("Same-app shortcut", isOn: $settings.sameAppShortcutEnabled)
                        .settingsDescription("A second shortcut that switches only between the active app's windows.")
                        .settingsAnchor("switcher.sameApp")
                    SettingsRow("Same-app keys", description: "Default ⌘`.") { ShortcutRecorder(shortcut: $settings.sameAppShortcut) }
                        .disabled(!settings.sameAppShortcutEnabled)
                }
                if mode == .windows {
                    SettingsSection("Windows") {
                        SettingsChoice(title: "Desktops", description: "Windows from the current desktop (Space), or from all of them.",
                                       value: $settings.switcherScope, labels: [.currentDesktop: "Current desktop", .allDesktops: "All desktops"])
                            .settingsAnchor("switcher.scope")
                        SettingsChoice(title: "Displays", description: "Windows from every monitor, or only the one under the pointer.",
                                       value: $settings.switcherScreens, choices: [.all, .withMouse],
                                       labels: [.all: "All displays", .withMouse: "Display with the pointer"])
                            .settingsAnchor("switcher.screens")
                        Toggle("Include minimized windows", isOn: $settings.switcherIncludeMinimized)
                            .settingsDescription("Selecting one restores it.")
                            .settingsAnchor("switcher.minimized")
                        Toggle("Include hidden apps", isOn: $settings.switcherIncludeHiddenApps)
                            .settingsDescription("Show windows of apps you've hidden.")
                            .settingsAnchor("switcher.hidden")
                        Toggle("Show apps without windows", isOn: $settings.switcherShowWindowlessApps)
                            .settingsDescription("Include running apps that have no windows to show.")
                            .settingsAnchor("switcher.windowless")
                    }
                } else {
                    SettingsSection("Apps") {
                        Toggle("Include hidden apps", isOn: $settings.switcherIncludeHiddenApps)
                            .settingsDescription("One icon per running app across all desktops, including apps with no open windows.")
                            .settingsAnchor("switcher.hidden")
                    }
                }
                SettingsSection("Panel") {
                    SettingsSlider(title: "Appearance delay", description: "Quick taps switch without showing the panel.",
                                   value: $settings.switcherAppearanceDelay, range: 0...1, step: 0.01, unit: "s")
                        .settingsAnchor("switcher.delay")
                    SettingsMore("switcher.more") {
                        if mode == .windows {
                            SettingsSlider(title: "Thumbnail width", description: "The width of each window tile.",
                                           value: $settings.switcherThumbnailWidth, range: 160...600, step: 1, unit: "pt")
                                .settingsAnchor("switcher.thumbnails")
                            SettingsSlider(title: "Thumbnail height", description: "The height of each window tile.",
                                           value: $settings.switcherThumbnailHeight, range: 100...400, step: 1, unit: "pt")
                        }
                        SettingsRow("Maximum tiles per row", description: "More tiles wrap onto another row.") {
                            Stepper(value: $settings.switcherMaxTilesPerRow, in: 1...10) { Text("\(settings.switcherMaxTilesPerRow)").monospacedDigit() }
                                .accessibilityLabel("Maximum tiles per row").accessibilityValue("\(settings.switcherMaxTilesPerRow)")
                        }
                        .settingsAnchor("switcher.tilesPerRow")
                    }
                }
                SettingsSection("Keys while switching", footer: "Press a key while the switcher is open.") {
                    SwitcherKeyActions(settings: settings, windows: mode == .windows)
                        .settingsAnchor("switcher.keys")
                }
            }
        }
    }

    private var switcherText: String {
        switch settings.switcherMode {
        case .windows: return "One tile per window. Release the shortcut to jump straight to it."
        case .apps: return "One icon per app, like macOS. The same-app shortcut still switches windows."
        case .native: return "Apple's ⌘Tab stays in charge. DogBar's Dock and previews keep working."
        }
    }
}

/// A feature's introduction: its demo, what it does in a line, and its main control.
private struct FeatureHero<Scene: View, Control: View>: View {
    let section: FeatureSection
    let title: String
    let text: String
    @ViewBuilder var scene: Scene
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            scene
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title.uppercased())
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.7).foregroundStyle(SettingsPalette.accent)
                    .accessibilityAddTraits(.isHeader)
                Text(title).font(.system(size: 17, weight: .bold)).tracking(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) { control }.padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SettingsPalette.surface)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RadialGradient(colors: [SettingsPalette.tint.opacity(0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 320)))
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SettingsPalette.line, lineWidth: 1))
        .shadow(color: Color(hex: 0x2B0A74).opacity(0.04), radius: 8, y: 3)
    }
}

/// W, M, H and Q as checkboxes with their key, two to a row.
private struct SwitcherKeyActions: View {
    @ObservedObject var settings: AppSettings
    let windows: Bool
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
            if windows {
                GridRow {
                    action("W", "Close window", $settings.switcherCloseWithW)
                    action("M", "Minimize window", $settings.switcherMinimizeWithM)
                }
            }
            GridRow {
                action("H", "Hide app", $settings.switcherHideWithH)
                action("Q", "Quit app", $settings.switcherQuitWithQ)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func action(_ key: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 7) {
                Text(key).font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                    .accessibilityHidden(true)
                Text(title)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("\(key) to \(title.lowercased())")
    }
}

/// Pins belong to a desktop. Re-import replaces only the current desktop's pins.
private struct PinnedAppsSection: View {
    @ObservedObject var pinnedApps: PinnedAppsStore
    @State private var confirmation = false
    @State private var desktopKey: String?
    var body: some View {
        SettingsSection("Pinned apps") {
            SettingsRow("This desktop's pins", description: "Every desktop keeps its own pins and order. Re-import copies Apple's Dock into this desktop only.") {
                Button("Re-import from Apple's Dock…") { desktopKey = pinnedApps.activeDesktopKey; confirmation = true }
                    .disabled(!pinnedApps.canEdit)
            }
            .settingsAnchor("dock.pins")
        }
        .onChange(of: pinnedApps.activeDesktopKey) { _, _ in confirmation = false }
        .alert("Replace pinned apps?", isPresented: $confirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-import", role: .destructive) {
                if pinnedApps.activeDesktopKey == desktopKey { pinnedApps.reimportNativeDock() }
            }
        } message: { Text("Replace this desktop’s pinned apps with the current native Dock list. Other desktops are unchanged.") }
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
