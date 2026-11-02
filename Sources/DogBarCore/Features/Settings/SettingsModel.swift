import AppKit
import Combine
import SwiftUI

/// The four Settings pages. Every feature lives together on Features, split into subsections.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", features = "Features", appearance = "Appearance", advanced = "Advanced"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .features: return "dock.rectangle"
        case .appearance: return "paintbrush.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }
    /// The sidebar icon tile's color, as System Settings colors its panes.
    var tileColor: Color {
        switch self {
        case .general, .advanced: return Color(nsColor: .systemGray)
        case .features: return Color(hex: 0x7B3FF2)
        case .appearance: return Color(nsColor: .systemBlue)
        }
    }
}

/// Subsections of the Features page, each with a demo, its main switch and its options.
enum FeatureSection: String, CaseIterable, Identifiable {
    case dock, previews, switcher
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dock: return "Dock & Desktops"
        case .previews: return "Previews"
        case .switcher: return "Switcher"
        }
    }
    var symbol: String {
        switch self {
        case .dock: return "menubar.dock.rectangle"
        case .previews: return "rectangle.stack"
        case .switcher: return "rectangle.on.rectangle"
        }
    }
    /// Scroll anchor of the subsection's top.
    var anchor: String { "features.\(rawValue)" }
}

@MainActor final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .general
}

/// Which Features subsection is under the top of the page. Only the sidebar observes it, so
/// scrolling never re-renders the page itself.
@MainActor final class SettingsOutline: ObservableObject {
    @Published private(set) var section: FeatureSection = .dock
    /// While a jump scrolls the page, sections passed on the way are not reported.
    private var heldUntil = Date.distantPast
    /// A deliberate move (sidebar click or search result): mark it now and hold it while the
    /// page scrolls there.
    func jump(to section: FeatureSection) {
        heldUntil = Date().addingTimeInterval(0.8)
        if self.section != section { self.section = section }
    }
    /// The section under the top of the page, reported while scrolling.
    func track(_ section: FeatureSection) {
        guard Date() >= heldUntil, self.section != section else { return }
        self.section = section
    }
}

@MainActor final class SettingsSearch: ObservableObject {
    @Published var text = ""
    /// Incremented by Command-F to move focus into the search field.
    @Published private(set) var focusRequest = 0
    func requestFocus() { focusRequest += 1 }
}

/// Whether the Settings window can actually be seen: open, not minimized, not hidden and not
/// fully covered. Cached pane hosts are only hidden, never removed, so they never receive
/// onDisappear; anything that animates or polls gates on this instead.
@MainActor final class SettingsVisibility: ObservableObject {
    @Published var isVisible = false
    /// Advances each time Settings opens, so feature demos play once per visit.
    @Published private(set) var session = 0
    func beginSession() { session += 1 }
}

/// Scroll-to, highlight and disclosure state shared by every page. Changes only on a search
/// selection, a sidebar subsection click or a disclosure toggle.
@MainActor final class SettingsReveal: ObservableObject {
    struct Request: Equatable {
        let pane: SettingsPane
        let anchor: String
        /// Scrolled to first, in case the anchor's row is not shown in the current mode.
        let fallback: String?
        let alignTop: Bool
        let id: Int
    }
    @Published private(set) var request: Request?
    @Published private(set) var expanded: Set<String> = []
    @Published private(set) var highlighted: String?
    private var count = 0
    private var clearHighlight: Task<Void, Never>?

    func isExpanded(_ group: String) -> Bool { expanded.contains(group) }
    func toggle(_ group: String) {
        if expanded.contains(group) { expanded.remove(group) } else { expanded.insert(group) }
    }
    func scroll(to anchor: String, in pane: SettingsPane, fallback: String? = nil, expanding groups: [String] = [],
                highlight: Bool = false, alignTop: Bool = false) {
        for group in groups where !expanded.contains(group) { expanded.insert(group) }
        count += 1
        request = Request(pane: pane, anchor: anchor, fallback: fallback, alignTop: alignTop, id: count)
        clearHighlight?.cancel()
        guard highlight else { highlighted = nil; return }
        highlighted = anchor
        clearHighlight = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.highlighted = nil
        }
    }
}

/// Settings uses the system's own colors so it sits with the native glass sidebar like any
/// macOS settings window. Purple appears only as the app's accent.
enum SettingsPalette {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    /// Grouped section fill, as in System Settings.
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 1, alpha: 0.75)
    })
    static let line = Color(nsColor: .separatorColor)
    static let text = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    /// Purple for small marks, lightened in Dark Mode to keep contrast.
    static let accent = OnboardingPalette.accent
    /// The app's accent for switches, sliders and selection.
    static let tint = Color.dynamic(light: 0x6E24E6, dark: 0x9C6BFF)
    static let success = Color(nsColor: .systemGreen)
    static let caution = Color(nsColor: .systemOrange)
}

/// Shared measures so every page has the same rhythm and every trailing control lines up.
enum SettingsMetrics {
    /// Width of pop-up menus and slider groups in the trailing column.
    static let controlColumn: CGFloat = 196
    /// Descriptions wrap before this width so they stay readable on wide windows.
    static let textMeasure: CGFloat = 380
    static let radius: CGFloat = 10
}

/// Small supporting art copied to `Contents/Resources/Settings` by the packaging scripts.
/// Scenes reuse the onboarding app icons and wallpapers through OnboardingAssets.
@MainActor enum SettingsAssets {
    /// Every file Settings expects. Scripts/onboarding_resources.py verifies the same list.
    static let requiredFiles = ["Mascot/guide.png", "Mascot/search.png"]
    private static var cache: [String: NSImage] = [:]
    private static var missing = Set<String>()

    static var root: URL? {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Settings"),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Settings")]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func image(_ relativePath: String) -> NSImage? {
        if let cached = cache[relativePath] { return cached }
        if missing.contains(relativePath) { return nil }
        guard let url = root?.appendingPathComponent(relativePath), let image = NSImage(contentsOf: url) else {
            missing.insert(relativePath)
            Log.system.error("Settings asset missing: \(relativePath, privacy: .public)")
            return nil
        }
        cache[relativePath] = image
        return image
    }
}

/// The mascot as a small decorative supporting image. Hidden from VoiceOver: nearby text carries
/// the meaning. Missing art collapses to nothing.
struct SettingsMascot: View {
    enum Pose: String { case guide, search }
    let pose: Pose
    var size: CGFloat
    var body: some View {
        if let image = SettingsAssets.image("Mascot/\(pose.rawValue).png") {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
