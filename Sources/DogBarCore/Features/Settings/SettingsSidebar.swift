import AppKit
import SwiftUI

/// The native sidebar: a search field, then the pages in labeled groups. With a query it lists
/// matching settings instead.
/// The split view item supplies the glass material; nothing here draws a background.
@MainActor struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var search: SettingsSearch
    let reveal: SettingsReveal
    @State private var selectedResult = 0

    private var results: [SettingsSearchEntry] { SettingsSearchIndex.results(for: search.text) }
    private var searching: Bool { !search.text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SidebarSearchField(text: $search.text, focusRequest: search.focusRequest, onMove: move, onSubmit: { open(selectedIndex) })
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 10)
            if searching { resultList } else { pageList }
        }
        .tint(SettingsPalette.tint)
        .onChange(of: search.text) { _, _ in selectedResult = 0 }
    }

    // MARK: Pages

    /// Native sidebar rows at the large size (taller rows, larger icons, more padding), grouped
    /// under the system's sidebar section headers.
    private var pageList: some View {
        List(selection: Binding<SettingsPane?>(
            get: { navigation.pane },
            set: { pane in if let pane, navigation.pane != pane { navigation.pane = pane } })) {
            ForEach(SettingsPane.Group.allCases) { group in
                if group.rawValue.isEmpty {
                    rows(group.panes)
                } else {
                    Section(group.rawValue) { rows(group.panes) }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .large)
    }

    private func rows(_ panes: [SettingsPane]) -> some View {
        ForEach(panes) { pane in
            Label { Text(pane.rawValue) } icon: { SettingsIconTile(symbol: pane.symbol, color: pane.tileColor) }
                .tag(pane)
        }
    }

    // MARK: Search

    private var selectedIndex: Int { min(selectedResult, max(0, results.count - 1)) }
    /// Arrow keys in the search field move the selection; Return opens it.
    private func move(_ delta: Int) -> Bool {
        guard searching, !results.isEmpty else { return false }
        selectedResult = (selectedIndex + delta + results.count) % results.count
        return true
    }
    private func open(_ index: Int) {
        guard results.indices.contains(index) else { return }
        let entry = results[index]
        selectedResult = index
        navigation.pane = entry.pane
        reveal.scroll(to: entry.anchor, in: entry.pane, fallback: "pane.top",
                      expanding: entry.group.map { [$0] } ?? [], highlight: true)
    }

    @ViewBuilder private var resultList: some View {
        let results = results
        if results.isEmpty {
            ContentUnavailableView.search(text: search.text.trimmingCharacters(in: .whitespaces))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)
        } else {
            List(selection: Binding<Int?>(get: { selectedIndex }, set: { index in if let index { open(index) } })) {
                Section(results.count == 1 ? "1 Result" : "\(results.count) Results") {
                    ForEach(results.indices, id: \.self) { index in
                        let entry = results[index]
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title)
                            Text(entry.note.map { "\(entry.path) · \($0)" } ?? entry.path)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 2)
                        .tag(index)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Search results")
        }
    }
}

/// A white symbol on a colored rounded square, as System Settings draws its panes.
struct SettingsIconTile: View {
    /// Sized for large sidebar rows.
    static let size: CGFloat = 24
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// AppKit's search field, at the large size macOS 26 sidebars use. Arrow keys and Return drive
/// the result list; Escape clears.
struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onMove: (Int) -> Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search"
        field.controlSize = .large
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search settings")
        context.coordinator.lastFocusRequest = focusRequest
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SidebarSearchField
        var lastFocusRequest = 0
        init(_ parent: SidebarSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): return parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): return parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard !parent.text.isEmpty else { return false }
                parent.text = ""; (control as? NSSearchField)?.stringValue = ""
                return true
            default: return false
            }
        }
    }
}
