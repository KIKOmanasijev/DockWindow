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
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let description { SettingsDescriptionText(description) }
            }
            Spacer(minLength: 0)
            accessory.fixedSize()
        }
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

@MainActor struct SettingsSlider: View {
    let title: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = "pt"
    var body: some View {
        SettingsControl(description: description) {
            HStack { Text(title); Spacer(); Text(String(format: step < 1 ? "%.2f %@" : "%.0f %@", value, unit)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $value, in: range, step: step).accessibilityLabel(title)
        }
    }
}

@MainActor struct SettingsChoice<Value: RawRepresentable & Hashable & CaseIterable>: View where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    let title: String
    let description: String
    @Binding var value: Value
    var choices: [Value]? = nil
    var body: some View {
        SettingsRow(title, description: description) {
            Picker(title, selection: $value) {
                ForEach(choices ?? Array(Value.allCases), id: \.self) { item in Text(settingsLabel(item.rawValue)).tag(item) }
            }.labelsHidden()
        }
    }
}

func settingsLabel(_ raw: String) -> String {
    let labels = ["currentDesktop": "Current desktop", "allDesktops": "All desktops", "withMouse": "Display with mouse", "main": "Main display", "all": "All displays", "perWindow": "One dot per window", "single": "Single dot", "none": "Do nothing", "cycle": "Cycle windows", "hudWindow": "HUD window", "reopen": "Application reopen"]
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

/// A titled card of rows separated by hairlines. Plain stacks avoid the grouped Form's
/// row reconciliation and layout cost.
@MainActor struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            rows
                .padding(.horizontal, 16).padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var rows: some View {
        if #available(macOS 15.0, *) {
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { row in
                        if row.id != subviews.first?.id { Divider().opacity(0.6) }
                        row.padding(.vertical, 10)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) { content }.padding(.vertical, 12)
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
                configuration.label
                if let description { SettingsDescriptionText(description) }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: configuration.$isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}
