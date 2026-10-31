import AppKit
import ApplicationServices
import Combine

/// Native Dock icon metadata. Frames use AppKit global coordinates for panel anchoring.
public struct NativeDockItem: Identifiable, Equatable {
    public var id: String { bundleURL?.absoluteString ?? title }
    public let title: String
    public let bundleIdentifier: String?
    public let bundleURL: URL?
    public let badgeLabel: String?
    public var frame: CGRect
}
/// Low-frequency badges plus AX selection notifications for native-Dock preview fallback.
@MainActor public final class NativeDockReader: ObservableObject {
    @Published public private(set) var items: [NativeDockItem] = []
    @Published public private(set) var hoveredItem: NativeDockItem?
    public var badges: [String: String] { Dictionary(items.compactMap { item in
        guard let bundle = item.bundleIdentifier, let badge = item.badgeLabel else { return nil }
        return (bundle, badge)
    }, uniquingKeysWith: { _, last in last }) }
    private var worker: DockReadingWorker?
    private var token: NSObjectProtocol?
    public init() {}
    deinit { worker?.stop(); if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) } }
    public func start() {
        guard worker == nil else { return }
        let worker = DockReadingWorker()
        self.worker = worker
        worker.start { [weak self] items, selected in
            DispatchQueue.main.async { [weak self, weak worker] in
                guard let self, self.worker === worker else { return }
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                func convert(_ item: NativeDockItem) -> NativeDockItem {
                    var value = item
                    value.frame.origin.y = top - item.frame.maxY
                    return value
                }
                let converted = items.map(convert)
                if self.items != converted { self.items = converted }
                let item = selected.map(convert)
                let hovered = item.flatMap { $0.frame.contains(NSEvent.mouseLocation) ? $0 : nil }
                if self.hoveredItem != hovered { self.hoveredItem = hovered }
            }
        }
        token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak worker] _ in worker?.refresh() }
    }
    public func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil; worker?.stop(); worker = nil; hoveredItem = nil; items = []
    }
}
private final class DockReadingWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.hristijan.dogbar.nativeDock", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var hub: AXObserverHub?
    private var pid: pid_t?
    private var list: AXUIElement?
    private var callback: (([NativeDockItem], NativeDockItem?) -> Void)?
    func start(callback: @escaping ([NativeDockItem], NativeDockItem?) -> Void) {
        queue.async {
            self.callback = callback
            self.hub = AXObserverHub { [weak self] _, _ in self?.refresh() }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.read() }
            timer.resume(); self.timer = timer
        }
    }
    func refresh() { queue.async { self.read() } }
    func stop() { queue.async { self.timer?.cancel(); self.timer = nil; self.hub?.stop(); self.hub = nil; self.callback = nil; self.list = nil } }
    private func read() {
        guard callback != nil, AXIsProcessTrusted() else { return }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            list = nil; callback?([], nil); return
        }
        if dock.processIdentifier != pid || list == nil {
            if let pid { hub?.remove(pid: pid) }
            pid = dock.processIdentifier
            let root = AXUIElementCreateApplication(dock.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.25)
            list = AXRead.children(root).first { AXRead.value($0, kAXRoleAttribute) as? String == kAXListRole }
            hub?.update(pid: dock.processIdentifier, windows: [])
            if let list { hub?.observe(pid: dock.processIdentifier, element: list, notification: kAXSelectedChildrenChangedNotification) }
        }
        guard let list else { return }
        func item(_ element: AXUIElement) -> NativeDockItem? {
            guard AXRead.value(element, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
                  let frame = AXRead.frame(element) else { return nil }
            let value = AXRead.value(element, kAXURLAttribute)
            let url = value as? URL ?? (value as? String).flatMap(URL.init(string:))
            return NativeDockItem(title: AXRead.value(element, kAXTitleAttribute) as? String ?? "", bundleIdentifier: url.flatMap { Bundle(url: $0)?.bundleIdentifier },
                                  bundleURL: url, badgeLabel: AXRead.value(element, "AXStatusLabel") as? String, frame: frame)
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &value) == .success else { self.list = nil; return }
        let items = AXRead.elements(value).compactMap(item)
        let selected = AXRead.elements(AXRead.value(list, kAXSelectedChildrenAttribute)).first.flatMap(item)
        callback?(items, selected)
    }
}
