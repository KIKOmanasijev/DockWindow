import AppKit
import QuartzCore

/// Layer-backed Dock surface. The display link exists only while the pointer tracks the Dock.
@MainActor final class DockView: NSView, NSDraggingSource {
    static let itemType = NSPasteboard.PasteboardType("com.dockwindow.dock-item")
    var items: [DockItem] = []
    var settings: AppSettings
    var indicators: [String: DotIndicators] = [:]
    var images: [String: NSImage] = [:]
    var launching: Set<String> = []
    var previewVisible = false { didSet { if previewVisible != oldValue { render() } } }
    var onClick: ((DockItem) -> Void)?
    var onMenu: ((DockItem, NSEvent) -> Void)?
    var onHover: ((DockItem?, CGRect) -> Void)?
    var onReorder: ((DockItem, Int, Bool) -> Void)?
    var onFiles: (([URL], DockItem) -> Void)?
    private let provider: any DockBackgroundProvider
    private let background: NSView
    private var layers: [String: DockIconLayer] = [:]
    private var separators: [String: CALayer] = [:]
    private let label = NSTextField(labelWithString: "")
    private var link: CADisplayLink?
    private var pointer: CGPoint?
    private var hoverID: String?
    private var backingStyle: String?
    private var pressed: DockItem?
    private var pressPoint = CGPoint.zero
    private var longPress: Task<Void, Never>?
    private var preDragItems: [DockItem] = []
    private var dragged: DockItem?
    private var insertion = 0
    private var dropID: String?
    private var geometry = DockLayout(kinds: [], bounds: .zero, position: .bottom, baseSize: 48, maximumSize: 96)
    var isDragging: Bool { dragged != nil }
    func iconFrame(for id: String) -> CGRect? {
        guard let index = items.firstIndex(where: { $0.id == id }), geometry.iconFrames.indices.contains(index) else { return nil }
        return geometry.iconFrames[index]
    }
    func containsInteractivePoint(_ point: CGPoint) -> Bool { geometry.containsInteractivePoint(point) }
    init(settings: AppSettings) {
        self.settings = settings; provider = DockBackgroundProviders.preferred(); background = provider.makeBackgroundView()
        super.init(frame: .zero)
        wantsLayer = true; addSubview(background)
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 13, weight: .medium); label.alignment = .center
        label.wantsLayer = true; label.layer?.cornerRadius = 7; label.layer?.masksToBounds = true
        label.backgroundColor = .windowBackgroundColor; label.drawsBackground = true; label.isHidden = true
        addSubview(label)
        registerForDraggedTypes([Self.itemType, .fileURL])
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() { super.layout(); render() }
    func stopTracking() {
        link?.invalidate(); link = nil; pointer = nil
        longPress?.cancel(); longPress = nil; hoverID = nil; onHover?(nil, .zero); render()
    }
    func track(_ point: CGPoint?) {
        pointer = point
        if point != nil {
            if link == nil {
                let next = displayLink(target: self, selector: #selector(tick(_:)))
                next.add(to: .main, forMode: .common); link = next
            }
        } else if link != nil { stopTracking() }
    }
    @objc private func tick(_ link: CADisplayLink) { render() }
    func render() {
        guard layer != nil else { return }
        let kinds = items.map(\.kind)
        geometry = DockLayout(kinds: kinds, bounds: bounds, position: settings.dockPosition, baseSize: settings.iconSize,
                              maximumSize: settings.magnificationEnabled ? settings.magnificationSize : settings.iconSize,
                              pointer: dragged == nil ? pointer : nil)
        let duration = link == nil && !Theme.reducesMotion(settings) ? 0.12 : 0
        CATransaction.begin(); CATransaction.setDisableActions(duration == 0); CATransaction.setAnimationDuration(duration)
        background.frame = geometry.background
        let style = "\(settings.panelMaterial.rawValue):\(settings.theme.rawValue):\(settings.iconSize)"
        if backingStyle != style {
            provider.updateBackgroundView(background, material: settings.panelMaterial, cornerRadius: min(30, settings.iconSize * 0.3), theme: settings.theme)
            appearance = Theme.appearance(settings.theme); backingStyle = style
        }
        let live = Set(items.map(\.id))
        for key in Array(layers.keys) where !live.contains(key) {
            if let old = layers.removeValue(forKey: key) {
                old.opacity = 0; old.transform = CATransform3DMakeScale(0.1, 0.1, 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { old.removeFromSuperlayer() }
            }
        }
        for key in Array(separators.keys) where !live.contains(key) { separators.removeValue(forKey: key)?.removeFromSuperlayer() }
        let custom = settings.dotColor
        let color = settings.useCustomDotColor ? NSColor(srgbRed: custom.red, green: custom.green, blue: custom.blue, alpha: custom.alpha) : NSColor.labelColor.withAlphaComponent(0.7)
        for (index, item) in items.enumerated() {
            let frame = geometry.iconFrames[index]
            if item.kind == .separator {
                let line = separators[item.id] ?? CALayer(); separators[item.id] = line
                if line.superlayer == nil { layer?.addSublayer(line) }
                line.backgroundColor = NSColor.separatorColor.cgColor
                line.frame = settings.dockPosition == .bottom ? CGRect(x: frame.midX, y: frame.minY, width: 1, height: frame.height) : CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: 1)
                continue
            }
            let icon = layers[item.id] ?? DockIconLayer()
            if layers[item.id] == nil { icon.opacity = 0; layer?.addSublayer(icon); layers[item.id] = icon }
            if dragged != nil, icon.frame != frame, !Theme.reducesMotion(settings) {
                let slide = CABasicAnimation(keyPath: "position")
                slide.fromValue = NSValue(point: icon.presentation()?.position ?? icon.position)
                slide.toValue = NSValue(point: CGPoint(x: frame.midX, y: frame.midY))
                slide.duration = 0.12; slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
                icon.add(slide, forKey: "reorder")
            }
            icon.frame = frame
            icon.opacity = item.isDimmed ? 0.5 : 1
            if dragged?.id == item.id { icon.opacity = 0.3 }
            icon.backgroundColor = dropID == item.id ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor : NSColor.clear.cgColor
            icon.cornerRadius = 10
            icon.update(image: images[item.id], badgeText: item.app?.badgeLabel, indicators: indicators[item.id] ?? .init(count: 0), color: color,
                        position: settings.dockPosition, scale: window?.backingScaleFactor ?? 2, reduceMotion: Theme.reducesMotion(settings))
            icon.bounce(position: settings.dockPosition, enabled: launching.contains(item.id) && settings.bounceOnLaunch && !Theme.reducesMotion(settings))
        }
        CATransaction.commit()
        let hovered = pointer.flatMap { geometry.hitTest($0, kinds: kinds) }
        let item = hovered.map { items[$0] }
        if item?.id != hoverID {
            hoverID = item?.id
            onHover?(item, hovered.map { geometry.iconFrames[$0] } ?? .zero)
        } else if let item, let hovered { onHover?(item, geometry.iconFrames[hovered]) }
        label.isHidden = item == nil || previewVisible || !settings.showAppNameLabels || dragged != nil
        if let item, let hovered {
            label.stringValue = item.app?.name ?? item.pinnedApp?.url.deletingPathExtension().lastPathComponent ?? "Trash"
            label.sizeToFit()
            let frame = geometry.iconFrames[hovered]
            let size = CGSize(width: min(bounds.width - 10, label.frame.width + 20), height: 25)
            var origin: CGPoint
            switch settings.dockPosition {
            case .bottom: origin = CGPoint(x: frame.midX - size.width / 2, y: frame.maxY + 10)
            case .left: origin = CGPoint(x: frame.maxX + 10, y: frame.midY - size.height / 2)
            case .right: origin = CGPoint(x: frame.minX - size.width - 10, y: frame.midY - size.height / 2)
            }
            origin.x = max(0, min(bounds.width - size.width, origin.x)); origin.y = max(0, min(bounds.height - size.height, origin.y))
            label.frame = CGRect(origin: origin, size: size)
        }
    }
    private func item(at point: CGPoint) -> DockItem? { geometry.hitTest(point, kinds: items.map(\.kind)).map { items[$0] } }
    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil); pressed = item(at: pressPoint)
        longPress?.cancel()
        if let pressed {
            longPress = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled, self.pressed?.id == pressed.id else { return }
                self.pressed = nil; self.onMenu?(pressed, event)
            }
        }
    }
    override func mouseUp(with event: NSEvent) {
        longPress?.cancel()
        if let pressed, item(at: convert(event.locationInWindow, from: nil))?.id == pressed.id { onClick?(pressed) }
        pressed = nil
    }
    override func rightMouseDown(with event: NSEvent) {
        if let item = item(at: convert(event.locationInWindow, from: nil)) { onMenu?(item, event) }
    }
    override func mouseDragged(with event: NSEvent) {
        longPress?.cancel()
        let point = convert(event.locationInWindow, from: nil)
        guard let pressed, pressed.kind == .application, pressed.id != DockCompositionPolicy.finderBundleIdentifier,
              hypot(point.x - pressPoint.x, point.y - pressPoint.y) > 5 else { return }
        self.pressed = nil; preDragItems = items; dragged = pressed
        let writer = NSPasteboardItem(); writer.setString(pressed.id, forType: Self.itemType)
        let dragItem = NSDraggingItem(pasteboardWriter: writer)
        let image = images[pressed.id] ?? NSImage(size: CGSize(width: 48, height: 48))
        dragItem.setDraggingFrame(CGRect(origin: point, size: CGSize(width: 48, height: 48)), contents: image)
        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let dragged {
            let local = window.map { convert($0.convertPoint(fromScreen: screenPoint), from: nil) } ?? screenPoint
            let remove = operation.isEmpty && geometry.isDragRemoval(at: local)
            if remove || operation == .move { onReorder?(dragged, insertion, remove) }
        }
        if operation.isEmpty { items = preDragItems }
        preDragItems = []; dragged = nil; dropID = nil; render()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        if sender.draggingPasteboard.string(forType: Self.itemType) != nil {
            guard let dragged else { return [] }
            insertion = max(1, min(items.firstIndex { $0.kind != .application } ?? items.count, geometry.insertionIndex(at: point)))
            if let old = items.firstIndex(where: { $0.id == dragged.id }) {
                let target = min(items.count - 1, insertion > old ? insertion - 1 : insertion)
                if old != target { items.remove(at: old); items.insert(dragged, at: target); insertion = target; render() }
            }
            return .move
        }
        let target = item(at: point)
        dropID = target?.id; render()
        return target?.kind == .trash || target?.app?.bundleURL != nil || target?.pinnedApp != nil ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropID = nil; render() }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if sender.draggingPasteboard.string(forType: Self.itemType) != nil { return dragged != nil }
        guard let target = item(at: convert(sender.draggingLocation, from: nil)),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onFiles?(urls, target); dropID = nil; render(); return true
    }
}
