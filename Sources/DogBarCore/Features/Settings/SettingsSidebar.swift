import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", dock = "Dock", switcher = "Switcher", previews = "Dock Previews", appearance = "Appearance", advanced = "Advanced"
    var id: String { rawValue }
    var detail: String {
        switch self {
        case .general: return "Startup, permissions and your DogBar session."
        case .dock: return "Choose what appears in your Dock and how it behaves."
        case .switcher: return "Switch between windows, apps, or use the macOS default."
        case .previews: return "Make window previews work the way you do."
        case .appearance: return "Adjust the appearance of your Dock and panels."
        case .advanced: return "Diagnostics and advanced configuration."
        }
    }
    var searchTerms: String {
        switch self {
        case .general: return "startup login permissions accessibility screen recording pause reset menu bar"
        case .dock: return "icons size resize hide pinned recent trash desktop windows click scroll"
        case .switcher: return "shortcut keyboard alt tab option command apps windows native minimized hidden thumbnails"
        case .previews: return "hover delay preview cpu ram memory new window performance"
        case .appearance: return "theme light dark color material opacity animation motion corners"
        case .advanced: return "debug logs private api subroles import pinned diagnostics"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .dock: return "dock.rectangle"
        case .switcher: return "rectangle.on.rectangle"
        case .previews: return "rectangle.stack.fill"
        case .appearance: return "paintpalette.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }
    /// Top and bottom of the icon tile gradient, in the style of System Settings.
    var tint: [Color] {
        switch self {
        case .general: return [Color(red: 0.62, green: 0.64, blue: 0.68), Color(red: 0.42, green: 0.44, blue: 0.49)]
        case .dock: return [Color(red: 0.28, green: 0.62, blue: 1.0), Color(red: 0.04, green: 0.40, blue: 0.94)]
        case .switcher: return [Color(red: 0.72, green: 0.50, blue: 1.0), Color(red: 0.50, green: 0.27, blue: 0.93)]
        case .previews: return [Color(red: 0.25, green: 0.84, blue: 0.86), Color(red: 0.0, green: 0.60, blue: 0.70)]
        case .appearance: return [Color(red: 1.0, green: 0.48, blue: 0.62), Color(red: 0.94, green: 0.22, blue: 0.43)]
        case .advanced: return [Color(red: 1.0, green: 0.68, blue: 0.26), Color(red: 0.95, green: 0.45, blue: 0.10)]
        }
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || (rawValue + " " + searchTerms).localizedCaseInsensitiveContains(query)
    }
}

@MainActor final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .general
    @Published var search = ""
}

/// Sidebar content. The surrounding split-view item supplies the translucent sidebar material.
@MainActor struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    private var matches: [SettingsPane] { SettingsPane.allCases.filter { $0.matches(navigation.search) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField.padding(.horizontal, 12)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(matches) { row($0) }
                    if matches.isEmpty {
                        Text("No matching sections").font(.callout).foregroundStyle(.secondary).padding(.top, 12)
                    }
                }.padding(.horizontal, 10)
            }
            Text("DogBar \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 22).padding(.bottom, 14)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField("Search settings", text: $navigation.search)
                .textFieldStyle(.plain)
                .onSubmit { if let first = matches.first { navigation.pane = first } }
            if !navigation.search.isEmpty {
                Button { navigation.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).frame(height: 30)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func row(_ item: SettingsPane) -> some View {
        let selected = navigation.pane == item
        return HStack(spacing: 10) {
            SettingsPaneIcon(pane: item)
            Text(item.rawValue).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if selected { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.1)) }
        }
        // Select on mouse-down, as AppKit sidebars do, instead of waiting for mouse-up.
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if navigation.pane != item { navigation.pane = item } })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { navigation.pane = item }
    }
}

@MainActor struct SettingsPaneIcon: View {
    let pane: SettingsPane
    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(LinearGradient(colors: pane.tint, startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
    }
}

/// Shared scrolling page for one pane: large title, summary and its sections.
@MainActor struct SettingsPaneContainer: View {
    let pane: SettingsPane
    let content: AnyView
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    SettingsPaneIcon(pane: pane).scaleEffect(1.4).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pane.rawValue).font(.system(size: 20, weight: .semibold))
                        Text(pane.detail).font(.callout).foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(SettingsToggleStyle())
        .controlSize(.regular)
    }
}
