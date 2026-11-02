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
                TableColumn("App") { rule in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appName(rule.bundleIdentifier))
                        Text(rule.bundleIdentifier).font(.system(size: 10.5)).foregroundStyle(SettingsPalette.muted)
                    }
                }
                TableColumn("Opens with") { rule in Text(settingsLabel(rule.strategy.rawValue)) }
            }
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            .frame(height: 150)
            .background(SettingsPalette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SettingsPalette.line, lineWidth: 1))
            .overlay {
                if settings.newWindowRules.isEmpty {
                    VStack(spacing: 3) {
                        Text("No rules").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(SettingsPalette.text)
                        Text("Automatic works for most apps. Add one that opens windows its own way.")
                            .font(.system(size: 11.5)).foregroundStyle(SettingsPalette.muted).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 30).padding(.top, 18)
                    .allowsHitTesting(false)
                }
            }
            HStack(spacing: 8) {
                Button("Add App…", action: addApp)
                    .help("Choose an installed application.")
                Button("Remove", role: .destructive) {
                    guard let selection else { return }
                    settings.newWindowRules.removeAll { $0.id == selection }; self.selection = nil
                }
                .disabled(selection == nil)
                .help("Return this app to automatic opening.")
                Spacer(minLength: 8)
                if selectedRule == nil && !settings.newWindowRules.isEmpty {
                    Text("Select an app to edit it.").font(.system(size: 11.5)).foregroundStyle(SettingsPalette.muted)
                }
            }
            if let rule = selectedRule {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsHairline()
                    SettingsChoice(title: "Try first", description: "The other ways follow if this one fails.", value: rule.strategy)
                        .padding(.vertical, 11)
                    SettingsHairline()
                    SettingsRow("New window shortcut", description: "The keys DogBar sends to this app.") { ShortcutRecorder(shortcut: rule.shortcut) }
                        .padding(.vertical, 11)
                    SettingsHairline()
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsRowText(title: Text("Menu titles"), description: "Exact menu item names in the app’s language, separated by semicolons.")
                        TextField("New Window; Nouvelle fenêtre", text: $menuTitlesText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Localized menu titles")
                            .onChange(of: menuTitlesText) { _, text in
                                rule.wrappedValue.menuTitles = text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                            }
                    }
                    .padding(.top, 11)
                }
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
        panel.prompt = "Add App"
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
