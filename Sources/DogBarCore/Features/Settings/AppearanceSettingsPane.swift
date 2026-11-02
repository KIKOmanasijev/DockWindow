import SwiftUI

@MainActor struct AppearanceSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Group {
            SettingsHero(title: "Panels", text: "The switcher and previews follow these. The preview here updates as you change them.") {
                PanelAppearancePreview(theme: settings.theme, selection: Theme.selection(settings), cornerRadius: settings.panelCornerRadius)
            } control: {
                SettingsRow("Theme") {
                    Picker("Theme", selection: $settings.theme) {
                        Text("Match macOS").tag(AppTheme.system)
                        Text("Light").tag(AppTheme.light)
                        Text("Dark").tag(AppTheme.dark)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                .settingsAnchor("appearance.theme")
            }
            SettingsSection("Style") {
                Toggle("Custom selection color", isOn: $settings.useCustomSelectionColor)
                    .settingsDescription("Instead of the system accent color.")
                    .settingsAnchor("appearance.selection")
                if settings.useCustomSelectionColor {
                    SettingsColorPicker(title: "Selection color", description: nil, value: $settings.selectionColor)
                }
                SettingsSlider(title: "Corner radius", description: nil,
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
                    .settingsDescription("Less motion in DogBar, on top of the macOS setting. Settings demos show stills.")
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
        stage(DemoMetrics.size)
            .padding(DemoMetrics.bezel)
            .background(RoundedRectangle(cornerRadius: DemoMetrics.radius + DemoMetrics.bezel, style: .continuous).fill(Color(hex: 0x0E0C13)))
            .overlay(RoundedRectangle(cornerRadius: DemoMetrics.radius + DemoMetrics.bezel + 1, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .padding(-1))
            .shadow(color: Color(hex: 0x14043C).opacity(0.28), radius: 14, y: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the switcher panel with the current theme, selection color and corner radius.")
    }
    private func stage(_ size: CGSize) -> some View {
        // Half scale, like the tiles: a 26 pt panel radius reads as 13 here.
        let radius = max(0, cornerRadius / 2)
        return Stage(wallpaper: "tahoe", size: size, radius: DemoMetrics.radius) {
            HStack(spacing: 5) {
                ForEach(tiles.indices, id: \.self) { index in
                    let tile = tiles[index], on = index == 1
                    VStack(spacing: 3) {
                        WindowThumb(kind: tile.kind)
                        AppIconImage(name: tile.app, size: 15).padding(.top, -10).shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        Text(tile.name).font(.system(size: 7.5, weight: .semibold)).lineLimit(1)
                            .foregroundStyle(dark ? Color(hex: 0xF3F0FA) : Color(hex: 0x1A1033))
                    }
                    .padding(5).frame(width: 72)
                    .background(RoundedRectangle(cornerRadius: max(2, radius * 0.55), style: .continuous)
                        .fill(on ? selection.opacity(0.55) : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: max(2, radius * 0.55), style: .continuous)
                        .strokeBorder(Color.white.opacity(on ? 0.6 : 0), lineWidth: 1))
                }
            }
            .padding(6)
            .glass(RoundedRectangle(cornerRadius: radius, style: .continuous), style: dark ? .dark : .light, shadow: 0.6)
        }
    }
}
