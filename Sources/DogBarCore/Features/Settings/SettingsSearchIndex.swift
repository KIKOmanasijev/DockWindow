import Foundation

/// One searchable setting: where its row lives and which collapsed group hides it.
struct SettingsSearchEntry: Identifiable, Hashable {
    let title: String
    let pane: SettingsPane
    var section: FeatureSection? = nil
    /// The row's `settingsAnchor`.
    let anchor: String
    var keywords = ""
    /// A `SettingsMore` group to open before scrolling.
    var group: String? = nil
    /// Shown when the row only exists in some modes.
    var note: String? = nil
    var id: String { anchor }
    var path: String { [pane.rawValue, section?.title].compactMap { $0 }.joined(separator: " › ") }
}

/// Every setting row, in page order. Rows and their anchors live in the pane files; a search
/// result scrolls to the anchor, opening its group and flashing the row.
enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = {
        typealias E = SettingsSearchEntry
        let dock = FeatureSection.dock, previews = FeatureSection.previews, switcher = FeatureSection.switcher
        return [
            // General
            E(title: "Pause DogBar", pane: .general, anchor: "general.pause", keywords: "suspend resume status running stop native dock"),
            E(title: "Launch at login", pane: .general, anchor: "general.login", keywords: "startup start sign in boot open login items"),
            E(title: "Show menu bar icon", pane: .general, anchor: "general.menubar", keywords: "paw menu status item hide"),
            E(title: "Show DogBar in the Dock", pane: .general, anchor: "general.dockicon", keywords: "app icon identity activation"),
            E(title: "Accessibility permission", pane: .general, anchor: "general.accessibility", keywords: "privacy access focus control trust"),
            E(title: "Screen Recording permission", pane: .general, anchor: "general.screenrecording", keywords: "privacy capture thumbnails images"),
            E(title: "Guided permission setup", pane: .general, anchor: "general.setup", keywords: "onboarding wizard tour permissions", group: "general.permissions.more"),
            E(title: "Relaunch DogBar", pane: .general, anchor: "general.relaunch", keywords: "restart quit reopen permissions", group: "general.permissions.more"),
            E(title: "Check for updates automatically", pane: .general, anchor: "general.updates", keywords: "software update sparkle version automatic"),
            E(title: "Check for updates now", pane: .general, anchor: "general.checknow", keywords: "software update sparkle version latest"),
            E(title: "Share anonymous usage data", pane: .general, anchor: "general.usage", keywords: "privacy telemetry analytics statistics"),
            E(title: "Restore Apple's Dock", pane: .general, anchor: "general.restore", keywords: "native dock recover recovery"),
            E(title: "Reset all settings", pane: .general, anchor: "general.reset", keywords: "defaults factory clear"),

            // Features › Dock & Desktops
            E(title: "Use DogBar Dock", pane: .features, section: dock, anchor: "dock.enabled", keywords: "replace native apple dock enable"),
            E(title: "Desktops a Dock shows apps from", pane: .features, section: dock, anchor: "dock.desktops", keywords: "spaces per desktop current all isolation scope"),
            E(title: "Displays a Dock shows apps from", pane: .features, section: dock, anchor: "dock.displays", keywords: "monitors screens current display scope"),
            E(title: "Apps on other desktops", pane: .features, section: dock, anchor: "dock.otherDesktops", keywords: "hide dimmed remote spaces"),
            E(title: "Hide apps with no open windows", pane: .features, section: dock, anchor: "dock.windowless", keywords: "windowless running recent"),
            E(title: "Include minimized windows", pane: .features, section: dock, anchor: "dock.minimized", keywords: "minimised", group: "dock.apps.more"),
            E(title: "Windowless apps on their last desktop", pane: .features, section: dock, anchor: "dock.lastDesktop", keywords: "running apps without windows spaces", group: "dock.apps.more"),
            E(title: "Pinned apps", pane: .features, section: dock, anchor: "dock.pins", keywords: "pins per desktop re-import import native favourites favorites"),
            E(title: "Dock position", pane: .features, section: dock, anchor: "dock.position", keywords: "edge bottom left right"),
            E(title: "Display with the Dock", pane: .features, section: dock, anchor: "dock.display", keywords: "monitor screen push move main pointer mouse"),
            E(title: "Icon size", pane: .features, section: dock, anchor: "dock.iconSize", keywords: "dock size scale big small"),
            E(title: "Automatically hide the Dock", pane: .features, section: dock, anchor: "dock.autohide", keywords: "autohide auto hide reveal"),
            E(title: "Autohide delay", pane: .features, section: dock, anchor: "dock.autohideDelay", keywords: "autohide auto hide wait", note: "With autohide on"),
            E(title: "Keep maximized windows clear of the Dock", pane: .features, section: dock, anchor: "dock.maximized", keywords: "zoom fill overlap"),
            E(title: "Show app name labels", pane: .features, section: dock, anchor: "dock.labels", keywords: "tooltip names hover"),
            E(title: "Clicking the active app", pane: .features, section: dock, anchor: "dock.click", keywords: "click cycle minimize hide"),
            E(title: "Scroll to cycle windows", pane: .features, section: dock, anchor: "dock.scroll", keywords: "scroll wheel trackpad"),
            E(title: "Bounce apps when they open", pane: .features, section: dock, anchor: "dock.bounce", keywords: "launch animation bounce"),
            E(title: "Show Trash", pane: .features, section: dock, anchor: "dock.trash", keywords: "bin trash can"),
            E(title: "Window dots", pane: .features, section: dock, anchor: "dock.indicators", keywords: "indicator style dots running"),
            E(title: "Maximum dots", pane: .features, section: dock, anchor: "dock.maxDots", keywords: "indicators dots count", note: "With one dot per window"),
            E(title: "Count minimized windows in dots", pane: .features, section: dock, anchor: "dock.countMinimized", keywords: "indicators minimised", group: "dock.indicators.more"),
            E(title: "Show running apps without windows", pane: .features, section: dock, anchor: "dock.runningState", keywords: "hollow ring indicator", group: "dock.indicators.more"),
            E(title: "Custom dot color", pane: .features, section: dock, anchor: "dock.dotColor", keywords: "indicator colour", group: "dock.indicators.more"),

            // Features › Previews
            E(title: "Dock previews", pane: .features, section: previews, anchor: "previews.enabled", keywords: "hover thumbnails enable window preview"),
            E(title: "Hover delay", pane: .features, section: previews, anchor: "previews.delay", keywords: "wait preview open speed"),
            E(title: "Preview windows from", pane: .features, section: previews, anchor: "previews.scope", keywords: "desktops spaces current all"),
            E(title: "Preview thumbnail height", pane: .features, section: previews, anchor: "previews.height", keywords: "thumbnail height size"),
            E(title: "Show window titles", pane: .features, section: previews, anchor: "previews.titles", keywords: "names labels"),
            E(title: "Show window controls", pane: .features, section: previews, anchor: "previews.trafficLights", keywords: "traffic lights close minimize fullscreen"),
            E(title: "New Window tile", pane: .features, section: previews, anchor: "previews.newWindow", keywords: "plus open another window"),
            E(title: "Include minimized windows in previews", pane: .features, section: previews, anchor: "previews.minimized", keywords: "minimised"),
            E(title: "Previews for apps without windows", pane: .features, section: previews, anchor: "previews.empty", keywords: "empty new window button", group: "previews.more"),
            E(title: "Show app CPU usage", pane: .features, section: previews, anchor: "previews.cpu", keywords: "processor performance resources", group: "previews.more"),
            E(title: "Show app memory usage", pane: .features, section: previews, anchor: "previews.ram", keywords: "ram memory resources", group: "previews.more"),
            E(title: "Point previews at the Dock icon", pane: .features, section: previews, anchor: "previews.pointer", keywords: "arrow tail callout", group: "previews.more"),
            E(title: "Live refresh interval", pane: .features, section: previews, anchor: "previews.refresh", keywords: "thumbnail update refresh live", group: "previews.more"),

            // Features › Switcher
            E(title: "Switcher mode", pane: .features, section: switcher, anchor: "switcher.mode", keywords: "windows apps macos native default command tab alt tab"),
            E(title: "Switcher shortcut", pane: .features, section: switcher, anchor: "switcher.shortcut", keywords: "keyboard hotkey option tab command tab record", note: "Windows and Apps modes"),
            E(title: "Same-app shortcut", pane: .features, section: switcher, anchor: "switcher.sameApp", keywords: "command grave backtick windows of app", note: "Windows and Apps modes"),
            E(title: "Switcher windows from", pane: .features, section: switcher, anchor: "switcher.scope", keywords: "desktops spaces current all", note: "Windows mode"),
            E(title: "Switcher displays", pane: .features, section: switcher, anchor: "switcher.screens", keywords: "monitors screens pointer mouse", note: "Windows mode"),
            E(title: "Include minimized windows in switcher", pane: .features, section: switcher, anchor: "switcher.minimized", keywords: "minimised", note: "Windows mode"),
            E(title: "Include hidden apps", pane: .features, section: switcher, anchor: "switcher.hidden", keywords: "hidden applications", note: "Windows and Apps modes"),
            E(title: "Show apps without windows", pane: .features, section: switcher, anchor: "switcher.windowless", keywords: "windowless running", note: "Windows mode"),
            E(title: "Switcher appearance delay", pane: .features, section: switcher, anchor: "switcher.delay", keywords: "wait quick switching panel", note: "Windows and Apps modes"),
            E(title: "Switcher thumbnail size", pane: .features, section: switcher, anchor: "switcher.thumbnails", keywords: "width height tile size", group: "switcher.more", note: "Windows mode"),
            E(title: "Maximum tiles per row", pane: .features, section: switcher, anchor: "switcher.tilesPerRow", keywords: "rows wrap columns", group: "switcher.more", note: "Windows and Apps modes"),
            E(title: "Keys while switching", pane: .features, section: switcher, anchor: "switcher.keys", keywords: "w close m minimize h hide q quit keyboard actions", note: "Windows and Apps modes"),

            // Appearance
            E(title: "Theme", pane: .appearance, anchor: "appearance.theme", keywords: "light dark mode system"),
            E(title: "Custom selection color", pane: .appearance, anchor: "appearance.selection", keywords: "accent colour custom"),
            E(title: "Corner radius", pane: .appearance, anchor: "appearance.radius", keywords: "rounded corners"),
            E(title: "Reduce animations", pane: .appearance, anchor: "appearance.motion", keywords: "motion accessibility animation"),
            E(title: "Fallback panel material", pane: .appearance, anchor: "appearance.material", keywords: "blur glass background material", group: "appearance.more"),

            // Advanced
            E(title: "New window rules", pane: .advanced, anchor: "advanced.rules", keywords: "per app strategy menu shortcut reopen localized"),
            E(title: "Debug logging", pane: .advanced, anchor: "advanced.debug", keywords: "diagnostics logs verbose"),
            E(title: "Log file", pane: .advanced, anchor: "advanced.log", keywords: "diagnostics reveal finder logs"),
            E(title: "Allowed window subroles", pane: .advanced, anchor: "advanced.subroles", keywords: "ax accessibility standard dialog window detection"),
            E(title: "Private API availability", pane: .advanced, anchor: "advanced.privateAPI", keywords: "symbols skylight diagnostics", group: "advanced.api.more"),
        ]
    }()

    /// Every word must appear in the title, path or keywords. Title matches rank first.
    static func results(for query: String) -> [SettingsSearchEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let matches = entries.filter { entry in
            let haystack = "\(entry.title) \(entry.path) \(entry.keywords)"
            return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
        let inTitle = matches.filter { entry in words.allSatisfy { entry.title.localizedCaseInsensitiveContains($0) } }
        return inTitle + matches.filter { !inTitle.contains($0) }
    }
}
