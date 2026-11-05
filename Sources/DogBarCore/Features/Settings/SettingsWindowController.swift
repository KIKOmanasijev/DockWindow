import AppKit
import Combine
import SwiftUI

/// Owns the focusable settings window and preserves the application's visible Dock identity.
@MainActor public final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let visibility: SettingsVisibility
    let navigation: SettingsNavigation
    let search: SettingsSearch
    let reveal: SettingsReveal
    private let settings: AppSettings
    private let content: SettingsContentController
    private var titleSubscription: AnyCancellable?
    /// Posted when Settings opens or closes. DogBar shows its own Dock icon while Settings is open.
    public static let presenceDidChange = Notification.Name("DogBar.SettingsPresenceDidChange")
    /// Whether the Settings window is open. While it is, DogBar is a regular app and its icon
    /// shows in either Dock, whatever "Show DogBar in the Dock" says.
    public private(set) static var isOpen = false {
        didSet { if oldValue != isOpen { NotificationCenter.default.post(name: presenceDidChange, object: nil) } }
    }

    public init(settings: AppSettings, permissions: PermissionsService, pinnedApps: PinnedAppsStore,
                updates: UpdatePreferences, agentActivity: AgentActivityCenter, onRestoreNativeDock: @escaping () -> Void, onShowPermissions: @escaping () -> Void) {
        self.settings = settings
        let navigation = SettingsNavigation()
        let search = SettingsSearch()
        let reveal = SettingsReveal()
        let visibility = SettingsVisibility()
        self.visibility = visibility; self.navigation = navigation; self.search = search; self.reveal = reveal
        content = SettingsContentController(navigation: navigation, reveal: reveal) { pane in
            switch pane {
            case .general:
                AnyView(GeneralSettingsPane(settings: settings, permissions: permissions, updates: updates, visibility: visibility,
                                            onRestoreNativeDock: onRestoreNativeDock, onShowPermissions: onShowPermissions))
            case .permissions:
                AnyView(PermissionsSettingsPane(permissions: permissions, visibility: visibility, onShowPermissions: onShowPermissions))
            case .license:
                // Only listed in paid builds (see `SettingsPane.isAvailable`).
                if let license = AppAccess.shared.license { AnyView(LicenseSettingsPane(license: license)) } else { AnyView(EmptyView()) }
            case .dock, .previews, .switcher:
                AnyView(FeaturesSettingsPane(settings: settings, pinnedApps: pinnedApps, pane: pane,
                                             navigation: navigation, visibility: visibility))
            case .appearance: AnyView(AppearanceSettingsPane(settings: settings))
            case .newWindows: AnyView(NewWindowsSettingsPane(settings: settings))
            case .diagnostics: AnyView(DiagnosticsSettingsPane(settings: settings))
            case .beta: AnyView(BetaSettingsPane(settings: settings, center: agentActivity, visibility: visibility))
            }
        }
        let split = NSSplitViewController()
        // A native sidebar item: AppKit's glass material, resizing, divider and titlebar handling.
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView:
            SettingsSidebar(navigation: navigation, search: search, reveal: reveal)))
        sidebar.minimumThickness = 210; sidebar.maximumThickness = 260; sidebar.canCollapse = false
        let detail = NSSplitViewItem(viewController: content)
        split.splitViewItems = [sidebar, detail]
        split.view.frame = NSRect(x: 0, y: 0, width: 940, height: 700)

        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 700),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                    backing: .buffered, defer: false)
        // The standard unified toolbar: the page's name as the title, over the page column.
        window.title = SettingsPane.general.rawValue
        let toolbar = NSToolbar(identifier: "DogBar.Settings")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.identifier = NSUserInterfaceItemIdentifier("DogBar.Settings")
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        window.minSize = NSSize(width: 820, height: 580)
        window.setContentSize(NSSize(width: 940, height: 700))
        window.onFind = { search.requestFocus() }
        window.onSelectPane = { index in
            guard SettingsPane.available.indices.contains(index) else { return }
            search.text = ""
            navigation.pane = SettingsPane.available[index]
        }
        super.init(window: window)
        toolbar.delegate = self
        toolbar.insertItem(withItemIdentifier: .sidebarTrackingSeparator, at: 0)
        window.delegate = self
        titleSubscription = navigation.$pane.sink { [weak window] pane in window?.title = pane.rawValue }
        if !window.setFrameUsingName("DogBar.Settings") { window.center() }
        window.setFrameAutosaveName("DogBar.Settings")
    }
    required init?(coder: NSCoder) { nil }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.sidebarTrackingSeparator] }
    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.sidebarTrackingSeparator] }
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { nil }

    /// Opens Settings on a given page by its sidebar title, for example "Beta".
    public func show(pageNamed name: String) {
        if let pane = SettingsPane(rawValue: name), pane.isAvailable { search.text = ""; navigation.pane = pane }
        show()
    }
    /// Brings Settings forward, including when DogBar is running as a menu bar app.
    public func show() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        Self.isOpen = true
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
        Self.isOpen = false
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
                  let next = SettingsPane.available.first(where: { self.hosts[$0] == nil }) else { self.prewarming = false; return }
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
                VStack(alignment: .leading, spacing: 24) {
                    // The page's name is the window title; this only marks the top for scrolling.
                    Color.clear.frame(height: 0).id("pane.top")
                    content
                }
                .padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            #if compiler(>=6.2)
            // Built with the macOS 26 SDK: content softly fades under the glass toolbar.
            .scrollEdgeEffectStyle(.soft, for: .top)
            #endif
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
        case let key? where key.count == 1 && "123456789".contains(key):
            onSelectPane?(Int(key)! - 1); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
