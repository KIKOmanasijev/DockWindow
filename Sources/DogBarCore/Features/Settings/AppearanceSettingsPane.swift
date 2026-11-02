import SwiftUI

@MainActor struct AppearanceSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Group {
            PanelAppearancePreview(theme: settings.theme, selection: Theme.selection(settings), cornerRadius: settings.panelCornerRadius)
            SettingsSection("Panels") {
                SettingsChoice(title: "Theme", description: "The switcher and previews follow macOS, or stay light or dark.",
                               value: $settings.theme, labels: [.system: "Match macOS", .light: "Light", .dark: "Dark"])
                    .settingsAnchor("appearance.theme")
                Toggle("Custom selection color", isOn: $settings.useCustomSelectionColor)
                    .settingsDescription("Highlight the selected window in your own color instead of the system accent.")
                    .settingsAnchor("appearance.selection")
                SettingsColorPicker(title: "Selection color", description: "The highlight behind the selected window.", value: $settings.selectionColor)
                    .disabled(!settings.useCustomSelectionColor)
                SettingsSlider(title: "Corner radius", description: "How round the switcher and preview panels are.",
                               value: $settings.panelCornerRadius, range: 0...48, step: 1, unit: "pt")
                    .settingsAnchor("appearance.radius")
                SettingsMore("appearance.more") {
                    SettingsChoice(title: "Fallback material", description: "Used only where Liquid Glass is unavailable.",
                                   value: $settings.panelMaterial,
                                   labels: [.hudWindow: "HUD", .popover: "Popover", .sidebar: "Sidebar", .menu: "Menu"])
                        .settingsAnchor("appearance.material")
                }
            }
            SettingsSection("Motion") {
                Toggle("Reduce animations", isOn: $settings.reduceAnimations)
                    .settingsDescription("Limit motion in DogBar, on top of the macOS Reduce Motion setting. Settings demos show stills.")
                    .settingsAnchor("appearance.motion")
            }
        }
    }
}

/// A still switcher panel on a wallpaper that follows the theme, selection color and corner
/// radius as they change. No animation and no live windows.
private struct PanelAppearancePreview: View {
    let theme: AppTheme
    let selection: Color
    let cornerRadius: Double
    @Environment(\.colorScheme) private var colorScheme
    private let tiles: [(kind: WindowThumb.Kind, app: String, name: String)] = [
        (.trip, "safari", "Lisbon day plan"), (.notes, "notes", "Packing list"), (.slack, "slack", "#lisbon-trip"),
    ]
    private var dark: Bool { theme == .dark || (theme == .system && colorScheme == .dark) }
    var body: some View {
        GeometryReader { proxy in stage(CGSize(width: proxy.size.width, height: 150)) }
            .frame(height: 150)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the switcher panel with the current theme, selection color and corner radius.")
    }
    private func stage(_ size: CGSize) -> some View {
        // Half scale, like the tiles: a 26 pt panel radius reads as 13 here.
        let radius = max(0, cornerRadius / 2)
        return Stage(wallpaper: "tahoe", size: size, radius: 14) {
            HStack(spacing: 6) {
                ForEach(tiles.indices, id: \.self) { index in
                    let tile = tiles[index], on = index == 1
                    VStack(spacing: 3) {
                        WindowThumb(kind: tile.kind)
                        AppIconImage(name: tile.app, size: 18).padding(.top, -12).shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        Text(tile.name).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                            .foregroundStyle(dark ? Color(hex: 0xF3F0FA) : Color(hex: 0x1A1033))
                    }
                    .padding(6).frame(width: 96)
                    .background(RoundedRectangle(cornerRadius: max(2, radius * 0.55), style: .continuous)
                        .fill(on ? selection.opacity(0.55) : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: max(2, radius * 0.55), style: .continuous)
                        .strokeBorder(Color.white.opacity(on ? 0.6 : 0), lineWidth: 1))
                }
            }
            .padding(8)
            .glass(RoundedRectangle(cornerRadius: radius, style: .continuous), style: dark ? .dark : .light, shadow: 0.6)
        }
    }
}
