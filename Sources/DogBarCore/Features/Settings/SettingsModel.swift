import AppKit
import Combine
import SwiftUI

/// The Settings pages, in sidebar order. Each feature has its own page; the sidebar groups
/// them under labels.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", permissions = "Permissions"
    case dock = "Dock & Desktops", previews = "Previews", switcher = "Switcher", appearance = "Appearance"
    case newWindows = "New Windows", diagnostics = "Diagnostics", beta = "Beta"
    case license = "License"
    var id: String { rawValue }
    /// License exists only in paid builds; free builds never show it.
    var isAvailable: Bool { self != .license || CommercialPolicy.current.isPaid }
    static let available = allCases.filter(\.isAvailable)

    /// Sidebar groups. The first has no label.
    enum Group: String, CaseIterable, Identifiable {
        case app = "", features = "Features", advanced = "Advanced"
        var id: String { rawValue }
        var panes: [SettingsPane] { SettingsPane.available.filter { $0.group == self } }
    }
    var group: Group {
        switch self {
        case .general, .permissions, .license: return .app
        case .dock, .previews, .switcher, .appearance: return .features
        case .newWindows, .diagnostics, .beta: return .advanced
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .permissions: return "hand.raised.fill"
        case .license: return "key.fill"
        case .dock: return "dock.rectangle"
        case .previews: return "rectangle.on.rectangle"
        case .switcher: return "square.stack.3d.forward.dottedline.fill"
        case .appearance: return "paintbrush.fill"
        case .newWindows: return "plus.rectangle.on.rectangle"
        case .diagnostics: return "stethoscope"
        case .beta: return "flask.fill"
        }
    }
    /// The sidebar icon tile's color, as System Settings colors its panes.
    var tileColor: Color {
        switch self {
        case .general, .diagnostics: return Color(nsColor: .systemGray)
        case .permissions: return Color(nsColor: .systemBlue)
        case .license: return Color(nsColor: .systemOrange)
        case .dock: return Color(hex: 0x7B3FF2)
        case .previews: return Color(nsColor: .systemOrange)
        case .switcher: return Color(nsColor: .systemIndigo)
        case .appearance: return Color(nsColor: .systemPink)
        case .newWindows: return Color(nsColor: .systemGreen)
        case .beta: return Color(nsColor: .systemTeal)
        }
    }
}

@MainActor final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .general
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
