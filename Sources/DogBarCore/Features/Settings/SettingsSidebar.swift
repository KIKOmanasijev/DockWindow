import AppKit
import SwiftUI

/// The sidebar: onboarding's purple, with glass details. Search, then the four pages, with the
/// Features subsections marked like onboarding's step dots. With a query it lists matching
/// settings instead of pages. It draws its own background; there is no AppKit sidebar material.
@MainActor struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var outline: SettingsOutline
    @ObservedObject var search: SettingsSearch
    let reveal: SettingsReveal
    @FocusState private var searchFocused: Bool
    @State private var selectedResult = 0

    private var results: [SettingsSearchEntry] { SettingsSearchIndex.results(for: search.text) }
    private var searching: Bool { !search.text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField.padding(.horizontal, 14).padding(.top, 8)
            Group {
                if searching { resultList } else { pageList }
            }
            .padding(.top, 14)
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Native pieces inside (the text field, its caret) render for a dark surface. The
        // backdrop sits outside this so it still follows the system appearance.
        .environment(\.colorScheme, .dark)
        .tint(.white)
        .background(SidebarBackdrop().ignoresSafeArea())
        .onChange(of: search.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: search.text) { _, _ in selectedResult = 0 }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            TextField("Search settings", text: $search.text, prompt: Text("Search settings").foregroundStyle(.white.opacity(0.6)))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .accessibilityLabel("Search settings")
                .onSubmit { open(selectedIndex) }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    guard searching else { return .ignored }
                    search.text = ""; return .handled
                }
            if !search.text.isEmpty {
                Button { search.text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            shape.fill(Color.white.opacity(searchFocused ? 0.2 : 0.13))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(searchFocused ? 0.75 : 0.38), .white.opacity(0.08)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: Color(hex: 0x14043C).opacity(0.25), radius: 3, y: 1)
        }
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }

    private var selectedIndex: Int { min(selectedResult, max(0, results.count - 1)) }
    private func move(_ delta: Int) -> KeyPress.Result {
        guard searching, !results.isEmpty else { return .ignored }
        selectedResult = (selectedIndex + delta + results.count) % results.count
        return .handled
    }
    private func open(_ index: Int) {
        guard results.indices.contains(index) else { return }
        let entry = results[index]
        selectedResult = index
        navigation.pane = entry.pane
        if let section = entry.section { outline.section = section }
        reveal.scroll(to: entry.anchor, in: entry.pane, fallback: entry.section?.anchor,
                      expanding: entry.group.map { [$0] } ?? [], highlight: true)
    }

    private var resultList: some View {
        let results = results
        return ScrollView {
            if results.isEmpty {
                emptySearch
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(results.count == 1 ? "1 setting" : "\(results.count) settings")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 10).padding(.bottom, 5)
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        SidebarResultRow(entry: entry, selected: index == selectedIndex) { open(index) }
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 12)
            }
        }
        .scrollIndicators(.never)
        .accessibilityLabel("Search results")
    }

    /// The curious dog, what was searched, and three searches that do find something.
    private var emptySearch: some View {
        VStack(spacing: 10) {
            SettingsMascot(pose: .search, size: 96)
            VStack(spacing: 4) {
                Text("Nothing matches “\(search.text.trimmingCharacters(in: .whitespaces))”")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).lineLimit(3)
                Text("Try one of these:").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.65))
            }
            HStack(spacing: 6) {
                ForEach(["hover", "shortcut", "desktop"], id: \.self) { word in
                    Button(word) { search.text = word; searchFocused = true }
                        .buttonStyle(SidebarChipStyle())
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 14).padding(.horizontal, 14)
    }

    // MARK: Pages

    private var pageList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarPageRow(pane: pane, selected: navigation.pane == pane) {
                        if navigation.pane != pane { navigation.pane = pane }
                    }
                    if pane == .features {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(FeatureSection.allCases) { subsectionRow($0) }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.never)
    }

    /// Jumps within the Features page. The subsection under the top of the page is marked with
    /// onboarding's current-step capsule.
    private func subsectionRow(_ section: FeatureSection) -> some View {
        let current = navigation.pane == .features && outline.section == section
        let jump = {
            navigation.pane = .features
            outline.section = section
            reveal.scroll(to: section.anchor, in: .features, alignTop: true)
        }
        return SidebarSubsectionRow(title: section.title, current: current, action: jump)
    }

    private var footer: some View {
        Text("DogBar \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 22).padding(.bottom, 14).padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Onboarding's welcome gradient with its two soft lights.
private struct SidebarBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [SettingsPalette.railTop, SettingsPalette.railMid, SettingsPalette.railBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.2), .clear], center: UnitPoint(x: 0.3, y: 0), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Color(hex: 0xFF8FD1, opacity: 0.16), .clear], center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 280)
        }
        // A thin light edge where the sidebar meets the page, like the rim of a glass pane.
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom).frame(width: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A page: glass icon tile and name. The selected page becomes a white chip with a purple tile.
private struct SidebarPageRow: View {
    let pane: SettingsPane
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            SidebarIconTile(symbol: pane.symbol, selected: selected)
            Text(pane.rawValue).font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? OnboardingPalette.ink : Color.white.opacity(0.92))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            if selected {
                shape.fill(Color.white.opacity(0.96))
                    .overlay(shape.strokeBorder(Color.white, lineWidth: 0.5))
                    .shadow(color: Color(hex: 0x14043C).opacity(0.3), radius: 6, y: 3)
            } else if hovering {
                shape.fill(Color.white.opacity(0.1))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Select on mouse-down, as AppKit sidebars do, instead of waiting for mouse-up.
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in select() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pane.rawValue)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
    }
}

/// One icon family: a white glyph on frosted glass, or on onboarding's purple when selected.
private struct SidebarIconTile: View {
    let symbol: String
    let selected: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background {
                if selected {
                    shape.fill(LinearGradient(colors: [Color(hex: 0x9B5CFF), Color(hex: 0x6E24E6)], startPoint: .top, endPoint: .bottom))
                } else {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(selected ? 0.45 : 0.5), .white.opacity(0.08)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .accessibilityHidden(true)
    }
}

/// A Features subsection, indented under the page name. The current one gets the yellow capsule.
private struct SidebarSubsectionRow: View {
    let title: String
    let current: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Capsule().fill(current ? SettingsPalette.yellow : Color.white.opacity(0.35))
                    .frame(width: current ? 12 : 5, height: 5)
            }
            .frame(width: 24)
            Text(title).font(.system(size: 12.5, weight: current ? .semibold : .regular))
                .foregroundStyle(.white.opacity(current ? 1 : hovering ? 0.9 : 0.72))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).frame(height: 27)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: current)
        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in action() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), in Features")
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}

/// A search result: where the setting lives, then its name.
private struct SidebarResultRow: View {
    let entry: SettingsSearchEntry
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? OnboardingPalette.ink : .white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.note.map { "\(entry.path) · \($0)" } ?? entry.path)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? OnboardingPalette.ink.opacity(0.6) : .white.opacity(0.62))
                    .lineLimit(2)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                if selected { shape.fill(Color.white.opacity(0.96)).shadow(color: Color(hex: 0x14043C).opacity(0.25), radius: 5, y: 2) }
                else if hovering { shape.fill(Color.white.opacity(0.1)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(entry.title)
        .accessibilityHint("In \(entry.path)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A suggested search, as a small glass capsule.
private struct SidebarChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 9).frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.28 : 0.16)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75))
            .contentShape(Capsule())
    }
}
