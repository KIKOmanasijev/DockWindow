import Foundation

/// One searchable setting: where its row lives and which collapsed group hides it.
struct SettingsSearchEntry: Identifiable, Hashable {
    let title: String
    let pane: SettingsPane
    /// The row's `settingsAnchor`.
    let anchor: String
    var keywords = ""
    /// A `SettingsMore` group to open before scrolling.
    var group: String? = nil
    /// Shown when the row only exists in some modes.
    var note: String? = nil
    var id: String { anchor }
    var path: String { pane.group.rawValue.isEmpty ? pane.rawValue : "\(pane.group.rawValue) › \(pane.rawValue)" }
}

/// Every setting row, in page order. Rows and their anchors live in the pane files; a search
/// result scrolls to the anchor, opening its group and flashing the row.
enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = {
        typealias E = SettingsSearchEntry
        return [
            // General
            E(title: "Pause DogBar", pane: .general, anchor: "general.pause", keywords: "suspend resume status running stop native dock"),
            E(title: "Launch at login", pane: .general, anchor: "general.login", keywords: "startup start sign in boot open login items"),
            E(title: "Show menu bar icon", pane: .general, anchor: "general.menubar", keywords: "paw menu status item hide"),
            E(title: "Show DogBar in the Dock", pane: .general, anchor: "general.dockicon", keywords: "app icon identity activation"),
            E(title: "Accessibility permission", pane: .permissions, anchor: "general.accessibility", keywords: "privacy access focus control trust"),
            E(title: "Screen Recording permission", pane: .permissions, anchor: "general.screenrecording", keywords: "privacy capture thumbnails images"),
            E(title: "Guided permission setup", pane: .permissions, anchor: "general.setup", keywords: "onboarding wizard tour permissions"),
            E(title: "Relaunch DogBar", pane: .permissions, anchor: "general.relaunch", keywords: "restart quit reopen permissions"),
            E(title: "Check for updates automatically", pane: .general, anchor: "general.updates", keywords: "software update sparkle version automatic"),
            E(title: "Check for updates now", pane: .general, anchor: "general.checknow", keywords: "software update sparkle version latest"),
            E(title: "Share anonymous usage data", pane: .general, anchor: "general.usage", keywords: "privacy telemetry analytics statistics"),
            E(title: "Restore Apple’s Dock", pane: .general, anchor: "general.restore", keywords: "native dock recover recovery"),
            E(title: "Reset all settings", pane: .general, anchor: "general.reset", keywords: "defaults factory clear"),

            E(title: "Activate a license", pane: .license, anchor: "license.activation", keywords: "license licence key purchase activate devices Macs"),

            // Dock & Desktops
            E(title: "Use DogBar’s Dock", pane: .dock, anchor: "dock.enabled", keywords: "replace native apple dock enable"),
            E(title: "Desktops a Dock shows apps from", pane: .dock, anchor: "dock.desktops", keywords: "spaces per desktop current all isolation scope"),
            E(title: "Displays a Dock shows apps from", pane: .dock, anchor: "dock.displays", keywords: "monitors screens current display scope"),
            E(title: "Apps on other desktops", pane: .dock, anchor: "dock.otherDesktops", keywords: "hide dimmed remote spaces"),
            E(title: "Hide apps with no open windows", pane: .dock, anchor: "dock.windowless", keywords: "windowless running recent"),
            E(title: "Include minimized windows", pane: .dock, anchor: "dock.minimized", keywords: "minimised", group: "dock.apps.more"),
            E(title: "Windowless apps on their last desktop", pane: .dock, anchor: "dock.lastDesktop", keywords: "running apps without windows spaces", group: "dock.apps.more"),
            E(title: "Pinned apps", pane: .dock, anchor: "dock.pins", keywords: "pins per desktop copy re-import import native apple favourites favorites"),
            E(title: "Dock position", pane: .dock, anchor: "dock.position", keywords: "edge bottom left right"),
            E(title: "Display with the Dock", pane: .dock, anchor: "dock.display", keywords: "monitor screen push move main pointer mouse"),
            E(title: "Icon size", pane: .dock, anchor: "dock.iconSize", keywords: "dock size scale big small"),
            E(title: "Automatically hide the Dock", pane: .dock, anchor: "dock.autohide", keywords: "autohide auto hide reveal"),
            E(title: "Autohide delay", pane: .dock, anchor: "dock.autohideDelay", keywords: "autohide auto hide wait", note: "With autohide on"),
            E(title: "Keep maximized windows clear of the Dock", pane: .dock, anchor: "dock.maximized", keywords: "zoom fill overlap"),
            E(title: "Show app names on hover", pane: .dock, anchor: "dock.labels", keywords: "tooltip labels names hover"),
            E(title: "Clicking the active app", pane: .dock, anchor: "dock.click", keywords: "click cycle minimize hide"),
            E(title: "Scroll to cycle windows", pane: .dock, anchor: "dock.scroll", keywords: "scroll wheel trackpad"),
            E(title: "Bounce apps while they open", pane: .dock, anchor: "dock.bounce", keywords: "launch animation bounce"),
            E(title: "Show Trash", pane: .dock, anchor: "dock.trash", keywords: "bin trash can"),
            E(title: "Window dots", pane: .dock, anchor: "dock.indicators", keywords: "indicator style dots running"),
            E(title: "Maximum dots", pane: .dock, anchor: "dock.maxDots", keywords: "indicators dots count", note: "With one dot per window"),
            E(title: "Count minimized windows in dots", pane: .dock, anchor: "dock.countMinimized", keywords: "indicators minimised", group: "dock.indicators.more"),
            E(title: "Mark running apps without windows", pane: .dock, anchor: "dock.runningState", keywords: "hollow ring indicator show", group: "dock.indicators.more"),
            E(title: "Custom dot color", pane: .dock, anchor: "dock.dotColor", keywords: "indicator colour", group: "dock.indicators.more"),

            // Previews
            E(title: "Dock previews", pane: .previews, anchor: "previews.enabled", keywords: "hover thumbnails enable window preview"),
            E(title: "Hover delay", pane: .previews, anchor: "previews.delay", keywords: "wait preview open speed"),
            E(title: "Preview windows from", pane: .previews, anchor: "previews.scope", keywords: "desktops spaces current all"),
            E(title: "Preview thumbnail height", pane: .previews, anchor: "previews.height", keywords: "thumbnail height size"),
            E(title: "Show window titles", pane: .previews, anchor: "previews.titles", keywords: "names labels"),
            E(title: "Show window controls", pane: .previews, anchor: "previews.trafficLights", keywords: "traffic lights close minimize fullscreen"),
            E(title: "New Window tile", pane: .previews, anchor: "previews.newWindow", keywords: "plus open another window"),
            E(title: "Include minimized windows in previews", pane: .previews, anchor: "previews.minimized", keywords: "minimised"),
            E(title: "Previews for apps without windows", pane: .previews, anchor: "previews.empty", keywords: "empty new window button", group: "previews.more"),
            E(title: "Show app CPU usage", pane: .previews, anchor: "previews.cpu", keywords: "processor performance resources", group: "previews.more"),
            E(title: "Show app memory usage", pane: .previews, anchor: "previews.ram", keywords: "ram memory resources", group: "previews.more"),
            E(title: "Point previews at the Dock icon", pane: .previews, anchor: "previews.pointer", keywords: "arrow tail callout", group: "previews.more"),
            E(title: "Live refresh interval", pane: .previews, anchor: "previews.refresh", keywords: "thumbnail update refresh live", group: "previews.more"),

            // Switcher
            E(title: "Switcher mode", pane: .switcher, anchor: "switcher.mode", keywords: "windows apps macos native default command tab alt tab"),
            E(title: "Switcher shortcut", pane: .switcher, anchor: "switcher.shortcut", keywords: "keyboard hotkey option tab command tab record", note: "Windows and Apps modes"),
            E(title: "Same-app shortcut", pane: .switcher, anchor: "switcher.sameApp", keywords: "command grave backtick windows of app", note: "Windows and Apps modes"),
            E(title: "Switcher windows from", pane: .switcher, anchor: "switcher.scope", keywords: "desktops spaces current all", note: "Windows mode"),
            E(title: "Switcher displays", pane: .switcher, anchor: "switcher.screens", keywords: "monitors screens pointer mouse", note: "Windows mode"),
            E(title: "Include minimized windows in switcher", pane: .switcher, anchor: "switcher.minimized", keywords: "minimised", note: "Windows mode"),
            E(title: "Include hidden apps", pane: .switcher, anchor: "switcher.hidden", keywords: "hidden applications", note: "Windows and Apps modes"),
            E(title: "Show apps without windows", pane: .switcher, anchor: "switcher.windowless", keywords: "windowless running", note: "Windows mode"),
            E(title: "Switcher appearance delay", pane: .switcher, anchor: "switcher.delay", keywords: "wait quick switching panel", note: "Windows and Apps modes"),
            E(title: "Switcher thumbnail size", pane: .switcher, anchor: "switcher.thumbnails", keywords: "width height tile size", group: "switcher.more", note: "Windows mode"),
            E(title: "Maximum tiles per row", pane: .switcher, anchor: "switcher.tilesPerRow", keywords: "rows wrap columns", group: "switcher.more", note: "Windows and Apps modes"),
            E(title: "Keys while switching", pane: .switcher, anchor: "switcher.keys", keywords: "w close m minimize h hide q quit keyboard actions panel", note: "Windows and Apps modes"),

            // Appearance
            E(title: "Theme", pane: .appearance, anchor: "appearance.theme", keywords: "light dark mode system match macos panels"),
            E(title: "Custom selection color", pane: .appearance, anchor: "appearance.selection", keywords: "accent colour custom"),
            E(title: "Corner radius", pane: .appearance, anchor: "appearance.radius", keywords: "rounded corners"),
            E(title: "Reduce animations", pane: .appearance, anchor: "appearance.motion", keywords: "motion accessibility animation"),
            E(title: "Fallback panel material", pane: .appearance, anchor: "appearance.material", keywords: "blur glass background material", group: "appearance.more"),

            // New Windows and Diagnostics
            E(title: "New window rules", pane: .newWindows, anchor: "advanced.rules", keywords: "per app strategy menu shortcut reopen localized"),
            E(title: "Debug logging", pane: .diagnostics, anchor: "advanced.debug", keywords: "diagnostics logs verbose"),
            E(title: "Log file", pane: .diagnostics, anchor: "advanced.log", keywords: "diagnostics reveal finder logs"),
            E(title: "Allowed window subroles", pane: .diagnostics, anchor: "advanced.subroles", keywords: "ax accessibility standard dialog window detection"),
            E(title: "Private API availability", pane: .diagnostics, anchor: "advanced.privateAPI", keywords: "symbols skylight diagnostics", group: "advanced.api.more"),

            // Beta
            E(title: "Agent Activity", pane: .beta, anchor: "beta.agentActivity", keywords: "claude code codex agents sessions notch island dog beta hooks"),
            E(title: "Always show the island", pane: .beta, anchor: "beta.alwaysVisible", keywords: "notch idle visible agent activity"),
            E(title: "Agent Activity connection", pane: .beta, anchor: "beta.connection", keywords: "socket events listening status hooks"),
            E(title: "Agent Activity sounds", pane: .beta, anchor: "beta.sounds", keywords: "audio cue chime notification alert"),
            E(title: "Reply from the island", pane: .beta, anchor: "beta.replies", keywords: "answer respond continue claude code asyncrewake"),
            E(title: "Agent Activity demo", pane: .beta, anchor: "beta.demo", keywords: "preview simulated try play"),
            E(title: "Claude Code hooks", pane: .beta, anchor: "beta.claude", keywords: "settings.json setup install remove uninstall configuration copy agent"),
            E(title: "Codex hooks", pane: .beta, anchor: "beta.codex", keywords: "hooks.json setup install remove uninstall configuration copy trust agent"),
        ].filter { $0.pane.isAvailable }
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
