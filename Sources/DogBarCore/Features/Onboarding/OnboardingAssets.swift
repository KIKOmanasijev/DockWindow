import AppKit
import SwiftUI

/// The four static mascot poses in `Contents/Resources/Onboarding/Mascot`.
public enum MascotPose: String, CaseIterable, Sendable {
    case welcome, guide, permissions, celebrate
}

/// Loads onboarding art copied into the app bundle by the packaging scripts.
/// Missing files fall back to the app icon or a plain shape, so the wizard always works.
@MainActor enum OnboardingAssets {
    static let mascotFiles = MascotPose.allCases.map { "Mascot/\($0.rawValue).png" }
    static let appNames = ["finder", "safari", "slack", "figma", "calendar", "notes", "mail", "chrome", "tv", "music", "photos", "messages", "trash"]
    static let wallpaperNames = ["tahoe", "sequoia-blue", "sequoia", "sonoma"]
    /// Every file the wizard expects. Packaging verifies the same list.
    static var requiredFiles: [String] {
        mascotFiles + MascotRig.layers.map { "Rig/\($0).png" }
            + appNames.map { "Product/apps/\($0).png" } + wallpaperNames.map { "Product/wallpapers/\($0).jpg" }
    }

    private static var cache: [String: NSImage] = [:]
    private static var missing = Set<String>()

    /// `Contents/Resources/Onboarding` in a bundle, or `Resources/Onboarding` when run unbundled from the repository.
    static var root: URL? {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Onboarding"),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Onboarding")]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func image(_ relativePath: String) -> NSImage? {
        if let cached = cache[relativePath] { return cached }
        if missing.contains(relativePath) { return nil }
        guard let url = root?.appendingPathComponent(relativePath), let image = NSImage(contentsOf: url) else {
            missing.insert(relativePath)
            Log.system.error("Onboarding asset missing: \(relativePath, privacy: .public)")
            return nil
        }
        cache[relativePath] = image
        return image
    }
    static func mascot(_ pose: MascotPose) -> NSImage {
        image("Mascot/\(pose.rawValue).png") ?? NSApp.applicationIconImage ?? NSImage()
    }
    static func app(_ name: String) -> NSImage? { image("Product/apps/\(name).png") }
    static func wallpaper(_ name: String) -> NSImage? { image("Product/wallpapers/\(name).jpg") }
}

/// The landing page's palette: deep purple hero, paper and ink, one yellow call to action.
enum OnboardingPalette {
    static let purple = Color(hex: 0x6E24E6)
    static let heroTop = Color(hex: 0x2B0A74)
    static let heroMid = Color(hex: 0x4A14B8)
    static let yellow = Color(hex: 0xFFC93C)
    static let yellowHover = Color(hex: 0xFFD766)
    static let yellowPressed = Color(hex: 0xF0B520)
    static let ink = Color(hex: 0x1A1033)
    static let paper = Color.dynamic(light: 0xF8F6FD, dark: 0x130E24)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1E1736)
    static let text = Color.dynamic(light: 0x1A1033, dark: 0xF3F0FA)
    static let muted = Color.dynamic(light: 0x5C5378, dark: 0xB6ADCF)
    static let line = Color.dynamic(light: 0xE5DFF2, dark: 0x30284F)
    /// Purple for text and small marks, lightened in Dark Mode to keep contrast.
    static let accent = Color.dynamic(light: 0x6E24E6, dark: 0xB794FF)
    static let success = Color.dynamic(light: 0x23854F, dark: 0x5BD08D)
    static let caution = Color.dynamic(light: 0x9A5B00, dark: 0xFFC66B)
    static var hero: LinearGradient {
        LinearGradient(colors: [heroTop, heroMid], startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// The single dominant action on each step: the landing page's yellow button.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    /// A smaller size for actions inside a card.
    var compact = false
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration, compact: compact) }
    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: compact ? 13.5 : 15, weight: .semibold))
                .foregroundStyle(OnboardingPalette.ink)
                .padding(.horizontal, compact ? 16 : 22)
                .frame(minWidth: compact ? 0 : 150, minHeight: compact ? 34 : 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
                .shadow(color: OnboardingPalette.ink.opacity(hovering && isEnabled ? 0.22 : 0.12), radius: hovering ? 10 : 6, y: 3)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        private var fill: Color {
            if configuration.isPressed { return OnboardingPalette.yellowPressed }
            return hovering && isEnabled ? OnboardingPalette.yellowHover : OnboardingPalette.yellow
        }
    }
}

/// Quiet text actions (Back, Skip, Show in Finder) with a visible hover and press state.
struct OnboardingQuietButtonStyle: ButtonStyle {
    var tint: Color = OnboardingPalette.accent
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration, tint: tint) }
    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.18 : hovering && isEnabled ? 0.1 : 0)))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// A bordered quiet button for secondary actions inside a card.
struct OnboardingBorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }
    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(OnboardingPalette.text)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(OnboardingPalette.accent.opacity(configuration.isPressed ? 0.16 : hovering && isEnabled ? 0.09 : 0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(OnboardingPalette.line))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Equal-weight choice buttons, used where neither answer should look preferred.
struct OnboardingChoiceButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration, selected: selected) }
    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(OnboardingPalette.text)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(OnboardingPalette.surface.opacity(configuration.isPressed ? 0.7 : 1)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? OnboardingPalette.accent : hovering ? OnboardingPalette.accent.opacity(0.5) : OnboardingPalette.line,
                                  lineWidth: selected ? 2 : 1))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
