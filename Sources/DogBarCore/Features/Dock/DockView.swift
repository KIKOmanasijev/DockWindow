import AppKit
import QuartzCore

/// Layer-backed Dock surface with fixed icon sizes and event-driven pointer tracking.
@MainActor final class DockView: NSView, NSDraggingSource {
    static let itemType = NSPasteboard.PasteboardType("dev.hristijan.dogbar.dock-item")
    var items: [DockItem] = []
    var settings: AppSettings
    var indicators: [String: DotIndicators] = [:]
    var images: [String: NSImage] = [:]
    var launching: Set<String> = []
    var previewVisible = false { didSet { if previewVisible != oldValue { render() } } }
    var onClick: ((DockItem) -> Void)?
    var onMenu: ((DockItem, NSEvent) -> Void)?
    var onResizeStarted: (() -> Void)?
    var onHover: ((DockItem?, CGRect) -> Void)?
    var onReorder: ((DockItem, Int, Bool) -> Void)?
    var onFiles: (([URL], DockItem) -> Void)?
    private let provider: any DockBackgroundProvider
    private let background: NSView
    private var layers: [String: DockIconLayer] = [:]
    private var separators: [String: CALayer] = [:]
    private let label = NSTextField(labelWithString: "")
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
    private var resizeSession: DockResizeSession?
    private var resizeMouseDown = false
    private var resizeHandle = CGRect.zero
    private let resizeGrip = CALayer()
    private let resizePill = CALayer()
    private var resizeCuePoint = CGPoint.zero
    private var lastFeedbackSize: CGFloat = 0
    private var cancelMonitor: Any?
    /// Item order at the last render; a change means apps came, went or the desktop changed.
    private var renderedIDs: [String] = []
    var isDragging: Bool { dragged != nil || resizeMouseDown }
    var ownsMouseSequence: Bool { pressed != nil || isDragging }
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
        finishResize(cancelled: true)
        resizeMouseDown = false
        pointer = nil
        longPress?.cancel(); longPress = nil; pressed = nil
        hoverID = nil; onHover?(nil, .zero); render()
        for icon in layers.values { icon.removeAllAnimations(); icon.imageLayer.removeAllAnimations(); icon.dots.removeAllAnimations() }
    }
    func track(_ point: CGPoint?) {
        guard !resizeMouseDown, pointer != point else { return }
        pointer = point
        if point == nil { hoverID = nil; onHover?(nil, .zero) }
        render()
    }
    func render() {
        guard layer != nil else { return }
        let kinds = items.map(\.kind)
        geometry = DockLayout(kinds: kinds, bounds: bounds, position: settings.dockPosition, baseSize: settings.iconSize,
                              maximumSize: settings.iconSize,
                              pointer: dragged == nil ? pointer : nil)
        // Keep every icon on whole device pixels. A half-pixel origin makes Core Animation
        // resample the raster, which is what made icons look soft.
        let scale = window?.backingScaleFactor ?? 2
        let snap = { (value: CGFloat) in (value * scale).rounded() / scale }
        geometry.iconFrames = geometry.iconFrames.map { CGRect(x: snap($0.minX), y: snap($0.minY), width: snap($0.width), height: snap($0.height)) }
        geometry.background = CGRect(x: snap(geometry.background.minX), y: snap(geometry.background.minY),
                                     width: snap(geometry.background.width), height: snap(geometry.background.height))
        // Like the system Dock: when apps arrive or leave, neighbours glide over, new icons
        // grow in and removed ones shrink away. Resizing and dragging stay immediate.
        let ids = items.map(\.id)
        let structural = !renderedIDs.isEmpty && ids != renderedIDs && !isDragging && resizeSession == nil && !Theme.reducesMotion(settings)
        renderedIDs = ids
        let duration = structural ? 0.32 : (pointer == nil && !isDragging && !Theme.reducesMotion(settings) ? 0.12 : 0)
        resizeHandle = geometry.resizeHandle(kinds: kinds)
        removeAllToolTips()
        window?.invalidateCursorRects(for: self)
        CATransaction.begin(); CATransaction.setDisableActions(duration == 0); CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1))
        if structural, background.frame != geometry.background {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                background.animator().frame = geometry.background
            }
        } else {
            background.frame = geometry.background
        }
        let style = "\(settings.panelMaterial.rawValue):\(settings.theme.rawValue):\(settings.iconSize)"
        if backingStyle != style {
            provider.updateBackgroundView(background, material: settings.panelMaterial, cornerRadius: min(30, settings.iconSize * 0.3), theme: settings.theme)
            appearance = Theme.appearance(settings.theme); backingStyle = style
        }
        let live = Set(items.map(\.id))
        for key in Array(layers.keys) where !live.contains(key) {
            if let old = layers.removeValue(forKey: key) {
                old.opacity = 0; old.transform = CATransform3DMakeScale(0.3, 0.3, 1)
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
            let isNew = layers[item.id] == nil
            if isNew { layer?.addSublayer(icon); layers[item.id] = icon }
            if isNew, structural {
                // A layer added in this transaction has no on-screen state to animate from,
                // so grow it in explicitly.
                let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 0.3; grow.toValue = 1
                let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1
                let group = CAAnimationGroup(); group.animations = [grow, fade]; group.duration = duration
                group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                icon.add(group, forKey: "arrive")
            }
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
                        position: settings.dockPosition, scale: scale, reduceMotion: Theme.reducesMotion(settings))
            icon.setPressed(pressed?.id == item.id && dragged == nil)
            icon.bounce(position: settings.dockPosition, enabled: launching.contains(item.id) && settings.bounceOnLaunch && !Theme.reducesMotion(settings))
        }
        if resizePill.superlayer == nil { layer?.addSublayer(resizePill) }
        if resizeGrip.superlayer == nil { layer?.addSublayer(resizeGrip) }
        let resizeArmed = resizeSession != nil || (!resizeMouseDown && pointer.map { geometry.containsResizeTarget($0, kinds: kinds) } == true)
        let accent = NSColor.systemPurple
        let edge = geometry.resizeEdge
        let point = resizeSession == nil ? (pointer ?? .zero) : resizeCuePoint
        let length = resizeSession == nil ? CGFloat(28) : 36
        let thickness = resizeSession == nil ? CGFloat(3) : 4
        if settings.dockPosition == .bottom {
            let width = min(length, edge.width)
            let x = min(max(point.x - width / 2, edge.minX), edge.maxX - width)
            resizePill.frame = CGRect(x: x, y: edge.midY - thickness / 2, width: width, height: thickness)
        } else {
            let height = min(length, edge.height)
            let y = min(max(point.y - height / 2, edge.minY), edge.maxY - height)
            resizePill.frame = CGRect(x: edge.midX - thickness / 2, y: y, width: thickness, height: height)
        }
        resizePill.name = "resize-pill"
        resizePill.backgroundColor = accent.cgColor
        resizePill.cornerRadius = thickness / 2
        resizePill.isHidden = !resizeArmed
        let hasSeparator = kinds.contains(.separator)
        let vertical = hasSeparator ? settings.dockPosition == .bottom : settings.dockPosition != .bottom
        resizeGrip.frame = CGRect(x: resizeHandle.midX - (vertical ? 1.5 : min(24, resizeHandle.width) / 2),
                                  y: resizeHandle.midY - (vertical ? min(24, resizeHandle.height) / 2 : 1.5),
                                  width: vertical ? 3 : min(24, resizeHandle.width),
                                  height: vertical ? min(24, resizeHandle.height) : 3)
        resizeGrip.cornerRadius = 1.5
        resizeGrip.isHidden = resizeHandle.isEmpty
        resizeGrip.backgroundColor = (resizeArmed ? accent : NSColor.labelColor.withAlphaComponent(0.3)).cgColor
        CATransaction.commit()
        let hovered = !resizeMouseDown ? pointer.flatMap { geometry.containsResizeTarget($0, kinds: kinds) ? nil : geometry.hitTest($0, kinds: kinds) } : nil
        let item = hovered.map { items[$0] }
        if item?.id != hoverID {
            hoverID = item?.id
            onHover?(item, hovered.map { geometry.iconFrames[$0] } ?? .zero)
        } else if let item, let hovered { onHover?(item, geometry.iconFrames[hovered]) }
        label.isHidden = resizeArmed || item == nil || previewVisible || !settings.showAppNameLabels || dragged != nil
        label.textColor = .labelColor
        if !resizeArmed, let item, let hovered {
            label.stringValue = item.app?.name ?? item.pinnedApp?.url.deletingPathExtension().lastPathComponent ?? "Trash"
            positionLabel(relativeTo: geometry.iconFrames[hovered])
        }
    }
    private func positionLabel(relativeTo frame: CGRect) {
        label.sizeToFit()
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
    private func item(at point: CGPoint) -> DockItem? { geometry.hitTest(point, kinds: items.map(\.kind)).map { items[$0] } }
    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        if geometry.containsResizeTarget(pressPoint, kinds: items.map(\.kind)) {
            longPress?.cancel(); longPress = nil; pressed = nil
            resizeMouseDown = true
            resizeCuePoint = pressPoint
            resizeSession = DockResizeSession(size: settings.iconSize, origin: NSEvent.mouseLocation, position: settings.dockPosition)
            lastFeedbackSize = settings.iconSize
            pointer = nil; hoverID = nil; onHover?(nil, .zero)
            onResizeStarted?()
            cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self, self.resizeSession != nil else { return event }
                self.finishResize(cancelled: true)
                return nil
            }
            resizeCursor.set(); render()
            return
        }
        pressed = item(at: pressPoint)
        if pressed != nil { render() }
        longPress?.cancel()
        if let pressed {
            longPress = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled, self.pressed?.id == pressed.id else { return }
                self.pressed = nil; self.render(); self.onMenu?(pressed, event)
            }
        }
    }
    override func mouseUp(with event: NSEvent) {
        if resizeMouseDown {
            finishResize(cancelled: false)
            resizeMouseDown = false; render()
            return
        }
        longPress?.cancel()
        let released = pressed
        pressed = nil; render()
        if let released, item(at: convert(event.locationInWindow, from: nil))?.id == released.id { onClick?(released) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let item = item(at: convert(event.locationInWindow, from: nil)) { onMenu?(item, event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if var resizeSession {
            let size = resizeSession.size(at: NSEvent.mouseLocation)
            self.resizeSession = resizeSession
            if size != settings.iconSize {
                settings.iconSize = size
                if abs(size - lastFeedbackSize) >= 16 {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
                    lastFeedbackSize = size
                }
            }
            resizeCursor.set(); render()
            return
        }
        if resizeMouseDown { return }
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
        preDragItems = []; dragged = nil; dropID = nil
        pointer = nil; render()
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
    private var resizeCursor: NSCursor {
        settings.dockPosition == .bottom ? .resizeUpDown : .resizeLeftRight
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if !resizeHandle.isEmpty { addCursorRect(resizeHandle, cursor: resizeCursor) }
        if !geometry.resizeEdge.isEmpty { addCursorRect(geometry.resizeEdge, cursor: resizeCursor) }
    }
    override func cancelOperation(_ sender: Any?) { finishResize(cancelled: true) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishResize(cancelled: true); resizeMouseDown = false }
        super.viewWillMove(toWindow: newWindow)
    }
    private func finishResize(cancelled: Bool) {
        guard var session = resizeSession else { return }
        settings.iconSize = session.end(at: NSEvent.mouseLocation, cancelled: cancelled)
        resizeSession = nil
        if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor); self.cancelMonitor = nil }
        pressed = nil; pointer = nil; hoverID = nil
        onHover?(nil, .zero); NSCursor.arrow.set(); render()
    }
    deinit {
        longPress?.cancel()
        if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) }
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if sender.draggingPasteboard.string(forType: Self.itemType) != nil { return dragged != nil }
        guard let target = item(at: convert(sender.draggingLocation, from: nil)),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onFiles?(urls, target); dropID = nil; render(); return true
    }
}
