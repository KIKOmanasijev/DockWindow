import AppKit
import Combine
import SwiftUI

/// Owns the focusable settings window and preserves the application's visible Dock identity.
@MainActor public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let visibility: SettingsVisibility
    private let settings: AppSettings
    private let content: SettingsContentController

    public init(settings: AppSettings, permissions: PermissionsService, pinnedApps: PinnedAppsStore,
                updates: UpdatePreferences, onRestoreNativeDock: @escaping () -> Void, onShowPermissions: @escaping () -> Void) {
        self.settings = settings
        let navigation = SettingsNavigation()
        let outline = SettingsOutline()
        let search = SettingsSearch()
        let reveal = SettingsReveal()
        let visibility = SettingsVisibility()
        self.visibility = visibility
        content = SettingsContentController(navigation: navigation, reveal: reveal) { pane in
            switch pane {
            case .general:
                AnyView(GeneralSettingsPane(settings: settings, permissions: permissions, updates: updates, visibility: visibility,
                                            onRestoreNativeDock: onRestoreNativeDock, onShowPermissions: onShowPermissions))
            case .features:
                AnyView(FeaturesSettingsPane(settings: settings, pinnedApps: pinnedApps, navigation: navigation,
                                             visibility: visibility, outline: outline))
            case .appearance: AnyView(AppearanceSettingsPane(settings: settings))
            case .advanced: AnyView(AdvancedSettingsPane(settings: settings))
            }
        }
        let split = NSSplitViewController()
        // A sidebar item gets AppKit's translucent, behind-window sidebar material.
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView:
            SettingsSidebar(navigation: navigation, outline: outline, search: search, reveal: reveal)))
        sidebar.minimumThickness = 220; sidebar.maximumThickness = 280; sidebar.canCollapse = false
        let detail = NSSplitViewItem(viewController: content)
        detail.titlebarSeparatorStyle = .none
        split.splitViewItems = [sidebar, detail]
        split.view.frame = NSRect(x: 0, y: 0, width: 940, height: 700)

        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 700),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                    backing: .buffered, defer: false)
        window.title = "DogBar Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.identifier = NSUserInterfaceItemIdentifier("DogBar.Settings")
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        window.minSize = NSSize(width: 820, height: 580)
        window.setContentSize(NSSize(width: 940, height: 700))
        window.onFind = { search.requestFocus() }
        window.onSelectPane = { index in
            guard SettingsPane.allCases.indices.contains(index) else { return }
            search.text = ""
            navigation.pane = SettingsPane.allCases[index]
        }
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("DogBar.Settings") { window.center() }
        window.setFrameAutosaveName("DogBar.Settings")
    }
    required init?(coder: NSCoder) { nil }

    /// Brings Settings forward, including when DogBar is running as a menu bar app.
    public func show() {
        NSApp.setActivationPolicy(settings.showDogBarInDock ? .regular : .accessory)
        if window?.isVisible != true { visibility.beginSession() }
        visibility.isVisible = true
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        content.prewarm()
    }
    public func windowDidMiniaturize(_ notification: Notification) { visibility.isVisible = false }
    public func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }
    /// Covers hiding the app, moving to another Space and being fully covered.
    public func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    public func windowWillClose(_ notification: Notification) {
        visibility.isVisible = false
        SettingsShortcutRecording.activeRecorder?.finish()
        NSApp.setActivationPolicy(settings.showDogBarInDock ? .regular : .accessory)
    }
    private func updateVisibility() {
        guard let window else { return }
        let visible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        if visibility.isVisible != visible { visibility.isVisible = visible }
    }
}

/// Keeps one hosting view per pane alive after it is first built. Switching panes only changes
/// which view is visible: rebuilding a pane's SwiftUI graph and its AppKit-backed controls on
/// every click was the visible delay between selecting a section and seeing it.
@MainActor final class SettingsContentController: NSViewController {
    private let navigation: SettingsNavigation
    private let reveal: SettingsReveal
    private let makePane: (SettingsPane) -> AnyView
    private var hosts: [SettingsPane: NSView] = [:]
    private var subscription: AnyCancellable?
    private var prewarming = false

    init(navigation: SettingsNavigation, reveal: SettingsReveal, makePane: @escaping (SettingsPane) -> AnyView) {
        self.navigation = navigation; self.reveal = reveal; self.makePane = makePane
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 700)) }
    override func viewDidLoad() {
        super.viewDidLoad()
        // @Published delivers before the property changes. Use the supplied value.
        subscription = navigation.$pane.removeDuplicates().sink { [weak self] pane in self?.show(pane) }
    }
    private func show(_ pane: SettingsPane) {
        SettingsShortcutRecording.activeRecorder?.finish()
        let selected = host(for: pane)
        for (key, host) in hosts where key != pane { host.isHidden = true }
        selected.isHidden = false
        // Keep keyboard focus out of controls that are no longer visible.
        if let responder = view.window?.firstResponder as? NSView, responder.isDescendant(of: view), !responder.isDescendant(of: selected) {
            view.window?.makeFirstResponder(nil)
        }
    }
    private func host(for pane: SettingsPane) -> NSView {
        if let host = hosts[pane] { return host }
        let host = NSHostingView(rootView: SettingsPaneContainer(pane: pane, reveal: reveal, content: makePane(pane)))
        // Let the window, not each pane's ideal size, decide the content size.
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = true
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor), host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosts[pane] = host
        return host
    }
    /// Builds the remaining panes one per main-queue turn while Settings is open, so even a
    /// section's first visit is immediate and no single turn blocks input for long.
    func prewarm() {
        guard !prewarming else { return }
        prewarming = true
        buildNextPane()
    }
    private func buildNextPane() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.view.window?.isVisible == true,
                  let next = SettingsPane.allCases.first(where: { self.hosts[$0] == nil }) else { self.prewarming = false; return }
            self.host(for: next).layoutSubtreeIfNeeded()
            self.buildNextPane()
        }
    }
}

/// Shared scrolling page for one pane: title, summary and its sections. Follows reveal
/// requests (search results and sidebar subsection jumps) addressed to this pane.
@MainActor struct SettingsPaneContainer: View {
    let pane: SettingsPane
    let reveal: SettingsReveal
    let content: AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var handled = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pane.rawValue).font(.system(size: 24, weight: .bold)).tracking(-0.4)
                            .accessibilityAddTraits(.isHeader)
                        Text(pane.detail).font(.system(size: 13)).foregroundStyle(SettingsPalette.muted)
                    }
                    .id("pane.top")
                    content
                }
                .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 32)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onReceive(reveal.$request) { request in follow(request, proxy: proxy) }
        }
        .background(SettingsPalette.canvas.ignoresSafeArea())
        .toggleStyle(SettingsToggleStyle())
        .tint(SettingsPalette.tint)
        .controlSize(.regular)
        .environmentObject(reveal)
    }

    private func follow(_ request: SettingsReveal.Request?, proxy: ScrollViewProxy) {
        guard let request, request.pane == pane, request.id != handled else { return }
        handled = request.id
        Task { @MainActor in
            // Let a page that was just shown, or a group that was just opened, lay out first.
            try? await Task.sleep(for: .milliseconds(40))
            if let fallback = request.fallback { proxy.scrollTo(fallback, anchor: .top) }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                proxy.scrollTo(request.anchor, anchor: request.alignTop ? .top : UnitPoint(x: 0.5, y: 0.3))
            }
        }
    }
}

/// Accessory apps do not always participate in main-menu key-equivalent routing.
/// Keep standard window commands available while Settings is the key window.
@MainActor final class SettingsWindow: NSWindow {
    var onFind: (() -> Void)?
    var onSelectPane: ((Int) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isKeyWindow, !SettingsShortcutRecording.isRecording,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": performClose(nil); return true
        case "q": NSApp.terminate(nil); return true
        case "f": onFind?(); return true
        case let key? where key.count == 1 && "1234".contains(key):
            onSelectPane?(Int(key)! - 1); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
