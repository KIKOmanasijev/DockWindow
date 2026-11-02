import AppKit
import Combine
import SwiftUI

/// The four Settings pages. Every feature lives together on Features, split into subsections.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", features = "Features", appearance = "Appearance", advanced = "Advanced"
    var id: String { rawValue }
    var detail: String {
        switch self {
        case .general: return "Startup, permissions, updates and privacy."
        case .features: return "Your Dock, window previews and the switcher."
        case .appearance: return "How DogBar's switcher and previews look."
        case .advanced: return "Per-app rules, diagnostics and window detection."
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .features: return "dock.rectangle"
        case .appearance: return "paintbrush.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }
    /// Top and bottom of the icon tile: onboarding's purple family, with ink for the quieter pages.
    var tint: [Color] {
        switch self {
        case .general: return [Color(hex: 0x8C86A3), Color(hex: 0x5E5778)]
        case .features: return [Color(hex: 0x9B5CFF), Color(hex: 0x6E24E6)]
        case .appearance: return [Color(hex: 0xE57BD0), Color(hex: 0xA43DD6)]
        case .advanced: return [Color(hex: 0x4F4570), Color(hex: 0x2B2245)]
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
    @Published var section: FeatureSection = .dock
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

/// Settings' slice of the onboarding palette: lavender paper, white surfaces, ink text and one
/// purple accent. Native controls keep the system text colors so they stay readable.
enum SettingsPalette {
    static let canvas = Color.dynamic(light: 0xF7F5FC, dark: 0x16112A)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1F1937)
    static let raised = Color.dynamic(light: 0xFBFAFE, dark: 0x251E40)
    static let line = Color.dynamic(light: 0xE6E0F2, dark: 0x332A52)
    static let muted = OnboardingPalette.muted
    static let accent = OnboardingPalette.accent
    /// Switches, sliders and selection marks.
    static let tint = Color.dynamic(light: 0x6E24E6, dark: 0x9C6BFF)
    static let success = OnboardingPalette.success
    static let caution = OnboardingPalette.caution
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
