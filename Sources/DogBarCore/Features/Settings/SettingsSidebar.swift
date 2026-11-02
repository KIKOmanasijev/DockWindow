import AppKit
import SwiftUI

/// Sidebar content for the native sidebar item. It paints the page canvas over AppKit's sidebar
/// material, so the window reads as one surface. Search, then the four pages; the Features
/// subsections show under Features while it is selected. With a query it lists matching
/// settings instead of pages.
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
        VStack(alignment: .leading, spacing: 12) {
            searchField.padding(.horizontal, 12)
            if searching { resultList } else { pageList }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsPalette.canvas.ignoresSafeArea())
        .tint(SettingsPalette.tint)
        .onChange(of: search.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: search.text) { _, _ in selectedResult = 0 }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(SettingsPalette.muted)
                .accessibilityHidden(true)
            TextField("Search", text: $search.text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
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
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(SettingsPalette.muted)
                }
                .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(searchFocused ? SettingsPalette.tint.opacity(0.55) : SettingsPalette.line, lineWidth: 1))
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
                VStack(spacing: 6) {
                    SettingsMascot(pose: .search, size: 72)
                    Text("No results for “\(search.text.trimmingCharacters(in: .whitespaces))”")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(SettingsPalette.text)
                        .multilineTextAlignment(.center).lineLimit(3)
                    Text("Try “hover”, “shortcut” or “desktop”.")
                        .font(.system(size: 11.5)).foregroundStyle(SettingsPalette.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.top, 12).padding(.horizontal, 14)
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 1) {
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

    // MARK: Pages

    private var pageList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarPageRow(pane: pane, selected: navigation.pane == pane) {
                        if navigation.pane != pane { navigation.pane = pane }
                    }
                    if pane == .features && navigation.pane == .features {
                        ForEach(FeatureSection.allCases) { subsectionRow($0) }
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.never)
    }

    /// Jumps within the Features page. The subsection under the top of the page is marked.
    private func subsectionRow(_ section: FeatureSection) -> some View {
        let jump = {
            navigation.pane = .features
            outline.section = section
            reveal.scroll(to: section.anchor, in: .features, alignTop: true)
        }
        return SidebarSubsectionRow(title: section.title, current: outline.section == section, action: jump)
    }
}

/// A page: its symbol and name. The selected page gets a quiet accent fill.
private struct SidebarPageRow: View {
    let pane: SettingsPane
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: pane.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? SettingsPalette.accent : SettingsPalette.muted)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(pane.rawValue).font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(SettingsPalette.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? SettingsPalette.tint.opacity(0.12) : hovering ? SettingsPalette.line.opacity(0.6) : .clear))
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

/// A Features subsection, indented to the page name. The current one is in the accent color.
private struct SidebarSubsectionRow: View {
    let title: String
    let current: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Text(title)
            .font(.system(size: 12.5, weight: current ? .medium : .regular))
            .foregroundStyle(current ? SettingsPalette.accent : hovering ? SettingsPalette.text : SettingsPalette.muted)
            .padding(.leading, 37).frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0).onEnded { _ in action() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), in Features")
            .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }
}

/// A search result: the setting's name, then where it lives.
private struct SidebarResultRow: View {
    let entry: SettingsSearchEntry
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(SettingsPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.note.map { "\(entry.path) · \($0)" } ?? entry.path)
                    .font(.system(size: 11)).foregroundStyle(SettingsPalette.muted).lineLimit(2)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? SettingsPalette.tint.opacity(0.12) : hovering ? SettingsPalette.line.opacity(0.6) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(entry.title)
        .accessibilityHint("In \(entry.path)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
