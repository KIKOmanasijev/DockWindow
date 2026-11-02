import AppKit
import SwiftUI

/// Sidebar content. The surrounding split-view item supplies the translucent sidebar material.
/// With a search query it lists matching settings instead of pages.
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
            Text("DogBar \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 22).padding(.bottom, 14)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: search.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: search.text) { _, _ in selectedResult = 0 }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search settings", text: $search.text)
                .textFieldStyle(.plain)
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
                Button { search.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).frame(height: 30)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(searchFocused ? SettingsPalette.tint.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: searchFocused ? 1 : 0.5))
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
                VStack(spacing: 8) {
                    SettingsMascot(pose: .search, size: 104)
                    Text("No settings match “\(search.text)”")
                        .font(.system(size: 12.5, weight: .semibold)).multilineTextAlignment(.center)
                    Text("Try “hover”, “shortcut” or “desktop”.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.top, 18).padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(results.count == 1 ? "1 setting" : "\(results.count) settings")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.bottom, 4)
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        resultRow(entry, selected: index == selectedIndex) { open(index) }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .accessibilityLabel("Search results")
    }

    private func resultRow(_ entry: SettingsSearchEntry, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: entry.section?.symbol ?? entry.pane.symbol)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(SettingsPalette.accent)
                    .frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.note.map { "\(entry.path) · \($0)" } ?? entry.path)
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.09)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.title)
        .accessibilityHint("In \(entry.path)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Pages

    private var pageList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    pageRow(pane)
                    if pane == .features {
                        ForEach(FeatureSection.allCases) { subsectionRow($0) }
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func pageRow(_ item: SettingsPane) -> some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { navigation.pane = item }
    }

    /// Jumps within the Features page. The subsection under the top of the page is marked.
    private func subsectionRow(_ section: FeatureSection) -> some View {
        let current = navigation.pane == .features && outline.section == section
        let jump = {
            navigation.pane = .features
            outline.section = section
            reveal.scroll(to: section.anchor, in: .features, alignTop: true)
        }
        return HStack(spacing: 8) {
            Circle().fill(current ? SettingsPalette.tint : Color.primary.opacity(0.22)).frame(width: 5, height: 5)
            Text(section.title).font(.system(size: 12, weight: current ? .semibold : .regular))
                .foregroundStyle(current ? Color.primary : Color.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 21).padding(.trailing, 8).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in jump() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section.title), in Features")
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { jump() }
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
            .accessibilityHidden(true)
    }
}
