import AppKit
import SwiftUI

@MainActor struct SettingsControl<Content: View>: View {
    let description: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            Text(description).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 7)
    }
}

@MainActor extension View {
    func settingsDescription(_ description: String) -> some View {
        SettingsControl(description: description) { self }
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
        Picker(title, selection: $value) {
            ForEach(choices ?? Array(Value.allCases), id: \.self) { item in Text(settingsLabel(item.rawValue)).tag(item) }
        }.settingsDescription(description)
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
        ColorPicker(title, selection: Binding(get: { Theme.color(value) }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            value = SettingsColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        })).settingsDescription(description)
    }
}

/// Lightweight native controls avoid the grouped Form's row reconciliation and layout.
@MainActor struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 20)
            Toggle("", isOn: configuration.$isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}
