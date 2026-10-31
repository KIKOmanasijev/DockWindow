import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor struct NewWindowRulesEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var selection: String?
    @State private var errorMessage: String?
    @State private var menuTitlesText = ""
    private var selectedRule: Binding<NewWindowRule>? {
        guard let selection, settings.newWindowRules.contains(where: { $0.id == selection }) else { return nil }
        return Binding(get: { settings.newWindowRule(for: selection) }, set: { updated in
            var rules = settings.newWindowRules
            guard let index = rules.firstIndex(where: { $0.id == selection }) else { return }
            rules[index] = updated; settings.newWindowRules = rules
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(settings.newWindowRules, selection: $selection) {
                TableColumn("Application") { rule in
                    VStack(alignment: .leading) {
                        Text(appName(rule.bundleIdentifier))
                        Text(rule.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                    }
                }
                TableColumn("Strategy") { rule in Text(settingsLabel(rule.strategy.rawValue)) }
            }.frame(height: 185)
                .settingsDescription("Select an app to edit its opening strategy, shortcut and localized menu titles.")
            HStack {
                Button("Add app", action: addApp)
                    .settingsDescription("Choose an installed application.")
                Button("Remove", role: .destructive) {
                    guard let selection else { return }
                    settings.newWindowRules.removeAll { $0.id == selection }; self.selection = nil
                }.disabled(selection == nil).settingsDescription("Return this app to automatic opening.")
            }
            if let rule = selectedRule {
                SettingsChoice(title: "Strategy", description: "Try this strategy first, followed by the remaining fallbacks.", value: rule.strategy)
                SettingsRow("New window shortcut", description: "Record a modifier and physical key to send to this application.") { ShortcutRecorder(shortcut: rule.shortcut) }
                TextField("Localized menu titles", text: $menuTitlesText, axis: .vertical)
                    .onChange(of: menuTitlesText) { _, text in
                        rule.wrappedValue.menuTitles = text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }
                    .settingsDescription("Separate exact menu titles with semicolons, using the app's language.")
            }
        }
        .onChange(of: selection) { _, _ in menuTitlesText = selectedRule?.wrappedValue.menuTitles.joined(separator: "; ") ?? "" }
        .onChange(of: settings.newWindowRules) { _, _ in
            let titles = selectedRule?.wrappedValue.menuTitles ?? []
            let draft = menuTitlesText.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if draft != titles { menuTitlesText = titles.joined(separator: "; ") }
            if let selection, !settings.newWindowRules.contains(where: { $0.id == selection }) { self.selection = nil }
        }
        .alert("Could not add app", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    private func appName(_ identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return identifier }
        return FileManager.default.displayName(atPath: url.path)
    }
    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an installed application"
        panel.prompt = "Add app"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty else {
                errorMessage = "Choose an application bundle with a valid bundle identifier."; return
            }
            if !settings.newWindowRules.contains(where: { $0.id == identifier }) {
                settings.newWindowRules.append(NewWindowRule(bundleIdentifier: identifier))
            }
            selection = identifier
        }
    }
}
