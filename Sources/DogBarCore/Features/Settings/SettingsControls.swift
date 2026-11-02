import AppKit
import SwiftUI

/// A control with a description underneath, for controls that need the full row width.
@MainActor struct SettingsControl<Content: View>: View {
    let description: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            SettingsDescriptionText(description)
        }
    }
}

/// Title and description on the leading side, a compact control on the trailing side.
@MainActor struct SettingsRow<Accessory: View>: View {
    let title: String
    let description: String?
    let accessory: Accessory
    init(_ title: String, description: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.description = description; self.accessory = accessory()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                if let description { SettingsDescriptionText(description) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory.fixedSize()
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .contain)
    }
}

@MainActor struct SettingsDescriptionText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor extension View {
    func settingsDescription(_ description: String) -> some View {
        SettingsControl(description: description) { self }
    }
    /// Makes this row a search and scroll target, with a brief highlight when revealed.
    func settingsAnchor(_ id: String) -> some View { modifier(SettingsAnchorModifier(id: id)) }
}

@MainActor extension Toggle {
    /// Toggles show their description beside the switch, under the title.
    func settingsDescription(_ description: String) -> some View {
        environment(\.settingsRowDescription, description)
    }
}

private struct SettingsRowDescriptionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsRowDescription: String? {
        get { self[SettingsRowDescriptionKey.self] }
        set { self[SettingsRowDescriptionKey.self] = newValue }
    }
}

private struct SettingsAnchorModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var reveal: SettingsReveal
    func body(content: Content) -> some View {
        let on = reveal.highlighted == id
        content
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsPalette.tint.opacity(on ? 0.13 : 0))
                    .padding(.horizontal, -8).padding(.vertical, -5)
                    .animation(.easeOut(duration: on ? 0.2 : 0.6), value: on)
            }
            .id(id)
    }
}

/// A row with a trailing slider and its value.
@MainActor struct SettingsSlider: View {
    let title: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = "pt"
    /// Shown instead of the value at zero, for example "Off".
    var zeroLabel: String? = nil
    var body: some View {
        SettingsRow(title, description: description) {
            HStack(spacing: 10) {
                // Rounded in the binding: a stepped Slider draws a tick for every step.
                Slider(value: Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }),
                       in: range) { Text(title) }
                    .labelsHidden().frame(width: 168)
                    .accessibilityValue(formatted)
                Text(formatted).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
    private var formatted: String {
        if value == 0, let zeroLabel { return zeroLabel }
        return String(format: step < 1 ? "%.2f %@" : "%.0f %@", value, unit)
    }
}

/// A row with a trailing pop-up menu. Labels default to `settingsLabel`.
@MainActor struct SettingsChoice<Value: RawRepresentable & Hashable & CaseIterable>: View where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    let title: String
    let description: String?
    @Binding var value: Value
    var choices: [Value]? = nil
    var labels: [Value: String] = [:]
    var body: some View {
        SettingsRow(title, description: description) {
            Picker(title, selection: $value) {
                ForEach(choices ?? Array(Value.allCases), id: \.self) { item in Text(labels[item] ?? settingsLabel(item.rawValue)).tag(item) }
            }.labelsHidden()
        }
    }
}

func settingsLabel(_ raw: String) -> String {
    let labels = ["allDisplays": "All displays", "currentDisplay": "Dock’s display only", "currentDesktop": "Current desktop", "allDesktops": "All desktops", "withMouse": "Display with pointer", "pushToMove": "Push at an edge to move", "main": "Main display", "all": "All displays", "perWindow": "One dot per window", "single": "Single dot", "none": "Do nothing", "cycle": "Cycle windows", "hudWindow": "HUD", "reopen": "Application reopen"]
    return labels[raw] ?? raw.prefix(1).uppercased() + raw.dropFirst()
}

@MainActor struct SettingsColorPicker: View {
    let title: String
    let description: String
    @Binding var value: SettingsColor
    var body: some View {
        SettingsRow(title, description: description) {
            ColorPicker(title, selection: Binding(get: { Theme.color(value) }, set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                value = SettingsColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
            })).labelsHidden()
        }
    }
}

/// Rows separated by hairlines. Plain stacks avoid the grouped Form's reconciliation cost.
@MainActor struct SettingsRows<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { row in
                    if row.id != subviews.first?.id { Divider().opacity(0.7) }
                    row.padding(.vertical, 10)
                }
            }
        }
    }
}

/// A titled group of rows on a white (or deep ink) surface.
@MainActor struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String? = nil
    let content: Content
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.footer = footer; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            SettingsRows { content }
                .padding(.horizontal, 14).padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsSurface()
            if let footer {
                SettingsDescriptionText(footer).padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func settingsSurface(radius: CGFloat = 12) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(SettingsPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(SettingsPalette.line, lineWidth: 1))
            .shadow(color: Color(hex: 0x2B0A74).opacity(0.035), radius: 6, y: 2)
    }
}

/// Rarely changed options, collapsed behind one quiet row inside a section. Search expands it.
@MainActor struct SettingsMore<Content: View>: View {
    let id: String
    var title = "More options"
    let content: Content
    @EnvironmentObject private var reveal: SettingsReveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ id: String, title: String = "More options", @ViewBuilder content: () -> Content) {
        self.id = id; self.title = title; self.content = content()
    }
    var body: some View {
        let expanded = reveal.isExpanded(id)
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                SettingsRows { content }.padding(.top, -10)
                Divider().opacity(0.7).padding(.top, 10)
            }
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { reveal.toggle(id) }
            } label: {
                HStack(spacing: 5) {
                    Text(expanded ? "Fewer options" : title)
                    Image(systemName: "chevron.down").font(.system(size: 9.5, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsPalette.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, expanded ? 10 : 0)
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides less common options" : "Shows less common options")
        }
    }
}

@MainActor struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { SettingsToggleRow(configuration: configuration) }
}

@MainActor private struct SettingsToggleRow: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.settingsRowDescription) private var description
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                configuration.label.fixedSize(horizontal: false, vertical: true)
                if let description { SettingsDescriptionText(description) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // VoiceOver reads the switch with its title and description, not the text twice.
            .accessibilityHidden(true)
            Toggle(isOn: configuration.$isOn) { configuration.label }.labelsHidden().toggleStyle(.switch)
                .accessibilityHint(description ?? "")
        }
        .frame(minHeight: 24)
    }
}

/// A quiet text button in the accent color, for Replay and similar inline actions.
struct SettingsQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }
    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsPalette.accent)
                .padding(.horizontal, 8).frame(minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SettingsPalette.tint.opacity(configuration.isPressed ? 0.16 : hovering && isEnabled ? 0.08 : 0)))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}
