import AppKit
import SwiftUI

// The building blocks every page uses. One row anatomy everywhere: title and an optional short
// description on the leading side, one control in a fixed-width trailing column, so menus and
// sliders line up down the page. Groups are a single quiet surface with hairlines between rows.

/// A control with a description underneath, for controls that need the full row width.
@MainActor struct SettingsControl<Content: View>: View {
    let description: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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
        HStack(alignment: .center, spacing: 20) {
            SettingsRowText(title: Text(title), description: description)
            accessory.fixedSize()
        }
        .frame(minHeight: 26)
        .accessibilityElement(children: .contain)
    }
}

/// The leading half of a row.
@MainActor struct SettingsRowText: View {
    let title: Text
    let description: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            title.font(.system(size: 13)).foregroundStyle(SettingsPalette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let description { SettingsDescriptionText(description) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor struct SettingsDescriptionText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(SettingsPalette.muted).lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: SettingsMetrics.textMeasure, alignment: .leading)
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
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SettingsPalette.tint.opacity(on ? 0.12 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(SettingsPalette.tint.opacity(on ? 0.35 : 0), lineWidth: 1))
                    .padding(.horizontal, -10).padding(.vertical, -6)
                    .animation(.easeOut(duration: on ? 0.2 : 0.7), value: on)
            }
            .id(id)
    }
}

/// A row with a trailing slider and its value.
@MainActor struct SettingsSlider: View {
    let title: String
    let description: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = "pt"
    /// Shown instead of the value at zero, for example "Off".
    var zeroLabel: String? = nil
    var body: some View {
        SettingsRow(title, description: description) {
            HStack(spacing: 8) {
                // Rounded in the binding: a stepped Slider draws a tick for every step.
                Slider(value: Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }),
                       in: range) { Text(title) }
                    .labelsHidden().controlSize(.small)
                    .accessibilityValue(formatted)
                Text(formatted).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(SettingsPalette.muted)
                    .frame(width: 52, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(width: SettingsMetrics.controlColumn)
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
            }
            .labelsHidden()
            .fixedSize()
            // macOS 26 pop-up buttons size to their title; right-align them as System Settings does.
            .frame(width: SettingsMetrics.controlColumn, alignment: .trailing)
        }
    }
}

func settingsLabel(_ raw: String) -> String {
    let labels = ["allDisplays": "All displays", "currentDisplay": "Dock’s display only", "currentDesktop": "Current desktop", "allDesktops": "All desktops", "withMouse": "Display with pointer", "pushToMove": "Push at an edge to move", "main": "Main display", "all": "All displays", "perWindow": "One dot per window", "single": "Single dot", "none": "Do nothing", "cycle": "Cycle windows", "hudWindow": "HUD", "reopen": "Application reopen"]
    return labels[raw] ?? raw.prefix(1).uppercased() + raw.dropFirst()
}

@MainActor struct SettingsColorPicker: View {
    let title: String
    let description: String?
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

/// The system separator between rows.
struct SettingsHairline: View {
    var body: some View { Divider() }
}

/// Rows separated by hairlines. Plain stacks avoid the grouped Form's reconciliation cost.
@MainActor struct SettingsRows<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { row in
                    if row.id != subviews.first?.id { SettingsHairline() }
                    row.padding(.vertical, 9)
                }
            }
        }
    }
}

/// A titled group of rows on one quiet surface.
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
                Text(title).font(.headline).foregroundStyle(SettingsPalette.text)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            SettingsRows { content }
                .padding(.horizontal, 14).padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsSurface()
            if let footer {
                SettingsDescriptionText(footer).padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// A grouped section's fill and edge, as System Settings draws them.
    func settingsSurface(radius: CGFloat = SettingsMetrics.radius) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(SettingsPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

/// Rarely changed options, collapsed behind one quiet row inside a section. Search expands it.
@MainActor struct SettingsMore<Content: View>: View {
    let id: String
    var title = "More options"
    let content: Content
    @EnvironmentObject private var reveal: SettingsReveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    init(_ id: String, title: String = "More options", @ViewBuilder content: () -> Content) {
        self.id = id; self.title = title; self.content = content()
    }
    var body: some View {
        let expanded = reveal.isExpanded(id)
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                SettingsRows { content }.padding(.top, -9)
                SettingsHairline()
            }
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) { reveal.toggle(id) }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded ? "Fewer options" : title)
                    Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12))
                .foregroundStyle(hovering ? SettingsPalette.text : SettingsPalette.muted)
                .frame(minHeight: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .padding(.top, expanded ? 9 : 0)
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
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                configuration.label.font(.system(size: 13)).foregroundStyle(SettingsPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let description { SettingsDescriptionText(description) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // VoiceOver reads the switch with its title and description, not the text twice.
            .accessibilityHidden(true)
            Toggle(isOn: configuration.$isOn) { configuration.label }.labelsHidden().toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityHint(description ?? "")
        }
        .frame(minHeight: 26)
    }
}

/// A status as macOS writes it: a colored symbol and a secondary label.
struct SettingsStatusPill: View {
    enum Tone { case good, warning, neutral }
    let text: String
    let symbol: String?
    let tone: Tone
    var body: some View {
        let color: Color = switch tone {
        case .good: SettingsPalette.success
        case .warning: SettingsPalette.caution
        case .neutral: SettingsPalette.muted
        }
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).foregroundStyle(color) }
            Text(text).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }
}

// MARK: - Page hero

/// The top of a page or feature, as one grouped section: its picture, name and one sentence,
/// then its main control in the same row layout as the rows below.
@MainActor struct SettingsHero<Visual: View, Detail: View, Control: View>: View {
    let title: String
    let text: String
    @ViewBuilder var visual: Visual
    @ViewBuilder var detail: Detail
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 20) {
                visual
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(SettingsPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(text).font(.system(size: 12)).foregroundStyle(SettingsPalette.muted).lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280, alignment: .leading)
                    detail
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            Divider()
            VStack(alignment: .leading, spacing: 0) { control }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .settingsSurface()
    }
}

extension SettingsHero where Detail == EmptyView {
    init(title: String, text: String, @ViewBuilder visual: () -> Visual, @ViewBuilder control: () -> Control) {
        self.title = title; self.text = text; self.visual = visual(); self.detail = EmptyView(); self.control = control()
    }
}
