import AppKit
import QuartzCore

/// Layer-backed Dock surface with fixed icon sizes and event-driven pointer tracking.
@MainActor final class DockView: NSView, NSDraggingSource {
    static let itemType = NSPasteboard.PasteboardType("dev.hristijan.dogbar.dock-item")
    var items: [DockItem] = []
    var pinProfileKey: String?
    var settings: AppSettings
    var indicators: [String: DotIndicators] = [:]
    var images: [String: NSImage] = [:]
    var launching: Set<String> = []
    var previewVisible = false { didSet { if previewVisible != oldValue { render() } } }
    var onClick: ((DockItem) -> Void)?
    var onMenu: ((DockItem, NSEvent) -> Void)?
    var onResizeStarted: (() -> Void)?
    /// Live geometry only; settings are persisted once when the drag ends.
    var onResizeChanged: ((CGFloat) -> Void)?
    var onHover: ((DockItem?, CGRect) -> Void)?
    var onReorder: ((DockItem, Int, Bool) -> Void)?
    var onFiles: (([URL], DockItem) -> Void)?
    private let provider: any DockBackgroundProvider
    private let background: NSView
    private let iconSurface = DockIconSurface()
    private var layers: [String: DockIconLayer] = [:]
    private var separators: [String: CALayer] = [:]
    private let label = NSTextField(labelWithString: "")
    private let labelBubble = NSView()
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
    /// Crisp outer rim plus a fainter inner line, both additive like the system Dock's edge.
    private let edgeRim = CAGradientLayer()
    private let edgeMask = CAShapeLayer()
    private let innerRim = CAGradientLayer()
    private let innerMask = CAShapeLayer()
    /// Restores the backdrop saturation that clear glass washes out (see `DockGlassStyle`).
    private let vibrance = CAShapeLayer()
    private let resizePill = CALayer()
    private var resizeCuePoint = CGPoint.zero
    private var cancelMonitor: Any?
    var reservedScreenDepth: CGFloat {
        guard !geometry.background.isEmpty else { return 0 }
        switch settings.dockPosition {
        case .bottom: return geometry.background.maxY - bounds.minY + 4
        case .left: return geometry.background.maxX - bounds.minX + 4
        case .right: return bounds.maxX - geometry.background.minX + 4
        }
    }
    var displayedIconSize: CGFloat { resizeSession?.currentSize ?? CGFloat(settings.iconSize) }
    var isDragging: Bool { dragged != nil || resizeMouseDown }
    var ownsMouseSequence: Bool { pressed != nil || isDragging }
    func iconFrame(for id: String) -> CGRect? {
        guard let index = items.firstIndex(where: { $0.id == id }), geometry.iconFrames.indices.contains(index) else { return nil }
        return geometry.iconFrames[index]
    }
    func containsInteractivePoint(_ point: CGPoint) -> Bool { geometry.containsInteractivePoint(point) }
    init(settings: AppSettings) {
        self.settings = settings; provider = DockBackgroundProviders.preferred(dock: true); background = provider.makeBackgroundView()
        super.init(frame: .zero)
        wantsLayer = true; addSubview(background)
        iconSurface.wantsLayer = true
        if background.responds(to: NSSelectorFromString("setContentView:")) {
            // Glass must own its content, so its sampling excludes our icons.
            background.setValue(iconSurface, forKey: "contentView")
        } else {
            addSubview(iconSurface)
        }
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 13, weight: .medium); label.alignment = .center
        label.drawsBackground = false
        labelBubble.wantsLayer = true; labelBubble.layer?.cornerRadius = 7
        labelBubble.layer?.masksToBounds = true; labelBubble.isHidden = true
        addSubview(labelBubble); labelBubble.addSubview(label)
        registerForDraggedTypes([Self.itemType, .fileURL])
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() { super.layout(); render() }
    /// System light/dark switches re-resolve the glass tint.
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsLayout = true }
    func stopTracking() {
        finishResize(cancelled: true)
        resizeMouseDown = false
        pointer = nil
        longPress?.cancel(); longPress = nil; pressed = nil
        hoverID = nil; onHover?(nil, .zero); render()
        for icon in layers.values { icon.removeAllAnimations(); icon.imageLayer.removeAllAnimations(); icon.dots.removeAllAnimations(); icon.dotHighlights.removeAllAnimations() }
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
        geometry = DockLayout(kinds: kinds, bounds: bounds, position: settings.dockPosition, baseSize: displayedIconSize,
                              maximumSize: displayedIconSize,
                              pointer: dragged == nil ? pointer : nil)
        // Keep every icon on whole device pixels. A half-pixel origin makes Core Animation
        // resample the raster, which is what made icons look soft.
        let scale = window?.backingScaleFactor ?? 2
        let snap = { (value: CGFloat) in (value * scale).rounded() / scale }
        geometry.iconFrames = geometry.iconFrames.map { CGRect(x: snap($0.minX), y: snap($0.minY), width: snap($0.width), height: snap($0.height)) }
        geometry.background = CGRect(x: snap(geometry.background.minX), y: snap(geometry.background.minY),
                                     width: snap(geometry.background.width), height: snap(geometry.background.height))
        // Layout is immediate. Only the containing Dock view moves at the screen edge;
        // individual icons never fly in from an old/zero position during a layout pass.
        resizeHandle = geometry.resizeHandle(kinds: kinds)
        removeAllToolTips()
        window?.invalidateCursorRects(for: self)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // Material and icons share one Core Animation transaction. AppKit's animator
        // proxy can defer the material resize to a later run-loop pass.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        background.frame = geometry.background
        background.layoutSubtreeIfNeeded()
        if iconSurface.superview === self {
            iconSurface.frame = bounds
        } else {
            iconSurface.frame = background.bounds
        }
        // Keep the existing Dock coordinate system inside the glass content view.
        iconSurface.bounds = iconSurface.superview === self ? bounds : geometry.background
        CATransaction.commit()
        background.layer?.removeAnimation(forKey: "dock-layout")
        let style = "\(settings.panelMaterial.rawValue):\(settings.theme.rawValue):\(geometry.cornerRadius):\(effectiveAppearance.name.rawValue)"
        if backingStyle != style {
            provider.updateBackgroundView(background, material: settings.panelMaterial, cornerRadius: geometry.cornerRadius, theme: settings.theme)
            appearance = Theme.appearance(settings.theme); backingStyle = style
        }
        let live = Set(items.map(\.id))
        for key in Array(layers.keys) where !live.contains(key) {
            layers.removeValue(forKey: key)?.removeFromSuperlayer()
        }
        for key in Array(separators.keys) where !live.contains(key) { separators.removeValue(forKey: key)?.removeFromSuperlayer() }
        let custom = settings.dotColor
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // In dark appearance default indicators are additive glass beads; light keeps ink dots.
        let glassDots = dark && !settings.useCustomDotColor
        let color = settings.useCustomDotColor ? NSColor(srgbRed: custom.red, green: custom.green, blue: custom.blue, alpha: custom.alpha)
            : glassDots ? DockGlassStyle.indicator : NSColor.labelColor.withAlphaComponent(0.7)
        for (index, item) in items.enumerated() {
            let frame = geometry.iconFrames[index]
            if item.kind == .separator {
                let line = separators[item.id] ?? CALayer(); separators[item.id] = line
                if line.superlayer == nil { iconSurface.layer?.addSublayer(line) }
                // Additive in dark appearance, so the line is a light streak in the glass.
                line.backgroundColor = (dark ? NSColor.white.withAlphaComponent(DockGlassStyle.separatorAlpha)
                                             : NSColor.labelColor.withAlphaComponent(0.22)).cgColor
                line.compositingFilter = dark ? "plusL" : nil
                let backing = geometry.background
                // The system Dock's separator stops one edge inset short of each material edge.
                let inset = geometry.edgeInset
                let pixel = { (value: CGFloat) in (value * scale).rounded() / scale }
                line.frame = settings.dockPosition == .bottom
                    ? CGRect(x: pixel(frame.midX), y: pixel(backing.minY + inset), width: 1, height: pixel(backing.height - 2 * inset))
                    : CGRect(x: pixel(backing.minX + inset), y: pixel(frame.midY), width: pixel(backing.width - 2 * inset), height: 1)
                continue
            }
            let icon = layers[item.id] ?? DockIconLayer()
            let isNew = layers[item.id] == nil
            if isNew { iconSurface.layer?.addSublayer(icon); layers[item.id] = icon }
            icon.removeAnimation(forKey: "arrive")
            icon.removeAnimation(forKey: "position")
            icon.removeAnimation(forKey: "bounds")
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
                        position: settings.dockPosition, scale: scale, reduceMotion: Theme.reducesMotion(settings),
                        baseSize: geometry.iconSize, glass: glassDots)
            icon.setPressed(pressed?.id == item.id && dragged == nil)
            icon.bounce(position: settings.dockPosition,
                        enabled: settings.bounceOnLaunch && launching.contains(item.id),
                        reduceMotion: Theme.reducesMotion(settings))
        }
        if resizePill.superlayer == nil { layer?.addSublayer(resizePill) }
        updateGlassEdge(dark: dark)
        // Only resize intent shows the pill: hovering or holding the top edge. Pressing or
        // holding an app icon must not, even if the pointer then slides onto the edge.
        let resizeArmed = resizeMouseDown || resizeSession != nil
            || (pressed == nil && dragged == nil && pointer.map { geometry.containsResizeTarget($0, kinds: kinds) } == true)
        let edge = geometry.resizeEdge
        let length: CGFloat = 28
        let thickness: CGFloat = 3
        if settings.dockPosition == .bottom {
            let width = min(length, edge.width)
            resizePill.frame = CGRect(x: edge.midX - width / 2, y: geometry.background.maxY + 6, width: width, height: thickness)
        } else {
            let height = min(length, edge.height)
            let x = settings.dockPosition == .left ? geometry.background.maxX + 6 : geometry.background.minX - 6 - thickness
            resizePill.frame = CGRect(x: x, y: edge.midY - height / 2, width: thickness, height: height)
        }
        resizePill.zPosition = 100
        resizePill.name = "resize-pill"
        resizePill.backgroundColor = NSColor.white.cgColor
        resizePill.cornerRadius = thickness / 2
        resizePill.isHidden = !resizeArmed
        CATransaction.commit()
        let hovered = !resizeMouseDown ? pointer.flatMap { geometry.containsResizeTarget($0, kinds: kinds) ? nil : geometry.hitTest($0, kinds: kinds) } : nil
        let item = hovered.map { items[$0] }
        if item?.id != hoverID {
            hoverID = item?.id
            onHover?(item, hovered.map { geometry.iconFrames[$0] } ?? .zero)
        } else if let item, let hovered { onHover?(item, geometry.iconFrames[hovered]) }
        labelBubble.isHidden = resizeArmed || item == nil || previewVisible || !settings.showAppNameLabels || dragged != nil
        label.textColor = .labelColor
        labelBubble.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        if !resizeArmed, let item, let hovered {
            label.stringValue = item.app?.name ?? item.pinnedApp?.url.deletingPathExtension().lastPathComponent ?? "Trash"
            positionLabel(relativeTo: geometry.iconFrames[hovered])
        }
    }
    /// Rim and saturation layers sit above the glass view, so their compositing filters blend
    /// with the rendered glass. They are sized to the material, never the whole panel.
    private func updateGlassEdge(dark: Bool) {
        let material = geometry.background, radius = geometry.cornerRadius
        if edgeRim.superlayer == nil {
            for (rim, mask) in [(edgeRim, edgeMask), (innerRim, innerMask)] {
                rim.mask = mask; rim.zPosition = 90
                rim.startPoint = CGPoint(x: 0.5, y: 1); rim.endPoint = CGPoint(x: 0.5, y: 0)
                // Additive: the rim brightens the glass beneath it, so it keeps the wallpaper's
                // hue like the system Dock's edge instead of painting a flat grey line.
                rim.compositingFilter = "plusL"
                mask.fillColor = NSColor.clear.cgColor; mask.strokeColor = NSColor.white.cgColor
                layer?.addSublayer(rim)
            }
            vibrance.zPosition = 1; vibrance.fillRule = .evenOdd
            vibrance.fillColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).cgColor
            vibrance.compositingFilter = "saturationBlendMode"
            layer?.addSublayer(vibrance)
        }
        // Light falls from above on every Dock edge, so the gradient always runs top to bottom.
        let profile = DockGlassStyle.rimProfile(length: material.height)
        for (rim, mask, peak, inset) in [(edgeRim, edgeMask, DockGlassStyle.rimAlpha, CGFloat(0)),
                                         (innerRim, innerMask, DockGlassStyle.innerRimAlpha, DockGlassStyle.rimWidth)] {
            rim.frame = material
            rim.isHidden = material.isEmpty
            rim.locations = profile.locations.map { NSNumber(value: Double($0)) }
            rim.colors = profile.weights.map { NSColor.white.withAlphaComponent(peak * $0).cgColor }
            mask.frame = rim.bounds
            mask.lineWidth = DockGlassStyle.rimWidth
            let half = DockGlassStyle.rimWidth / 2
            let rect = rim.bounds.insetBy(dx: inset + half, dy: inset + half)
            let r = max(0, min(radius - inset - half, min(rect.width, rect.height) / 2))
            mask.path = rect.isEmpty ? nil : CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }
        vibrance.frame = bounds
        vibrance.opacity = dark ? DockGlassStyle.darkVibrance : DockGlassStyle.lightVibrance
        vibrance.path = DockGlassStyle.vibrancePath(material: material, radius: radius,
                                                    icons: zip(items, geometry.iconFrames).filter { $0.0.kind != .separator && $0.0.kind != .trash }.map(\.1))
    }
    private func positionLabel(relativeTo frame: CGRect) {
        label.sizeToFit()
        let textHeight = label.frame.height
        let size = CGSize(width: min(bounds.width - 10, label.frame.width + 20), height: max(25, textHeight + 8))
        var origin: CGPoint
        switch settings.dockPosition {
        case .bottom: origin = CGPoint(x: frame.midX - size.width / 2, y: geometry.background.maxY + 8)
        case .left: origin = CGPoint(x: geometry.background.maxX + 8, y: frame.midY - size.height / 2)
        case .right: origin = CGPoint(x: geometry.background.minX - size.width - 8, y: frame.midY - size.height / 2)
        }
        origin.x = max(0, min(bounds.width - size.width, origin.x)); origin.y = max(0, min(bounds.height - size.height, origin.y))
        let scale = window?.backingScaleFactor ?? 2
        origin.x = (origin.x * scale).rounded() / scale
        origin.y = (origin.y * scale).rounded() / scale
        labelBubble.frame = CGRect(origin: origin, size: size)
        // NSTextField draws at the top of a tall frame. Keep its natural height
        // and centre that frame inside the padded bubble instead.
        label.frame = CGRect(x: 10, y: ((size.height - textHeight) * scale / 2).rounded() / scale,
                             width: max(0, size.width - 20), height: textHeight)
    }
    private func item(at point: CGPoint) -> DockItem? { geometry.hitTest(point, kinds: items.map(\.kind)).map { items[$0] } }
    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        if geometry.containsResizeTarget(pressPoint, kinds: items.map(\.kind)) {
            longPress?.cancel(); longPress = nil; pressed = nil
            resizeMouseDown = true
            resizeCuePoint = pressPoint
            resizeSession = DockResizeSession(size: settings.iconSize, origin: screenPoint(for: event), position: settings.dockPosition)
            // A live drag owns the geometry immediately, even if an app-arrival or
            // background resize animation was still running when it was grabbed.
            background.layer?.removeAllAnimations()
            for icon in layers.values { icon.removeAllAnimations() }
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
        render()
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
            finishResize(cancelled: false, point: screenPoint(for: event))
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
            let previousSize = resizeSession.currentSize
            let size = resizeSession.size(at: screenPoint(for: event))
            self.resizeSession = resizeSession
            if size != previousSize {
                onResizeChanged?(size)
            }
            resizeCursor.set(); render()
            return
        }
        if resizeMouseDown { return }
        longPress?.cancel()
        let point = convert(event.locationInWindow, from: nil)
        guard let pressed, pressed.kind == .application,
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
    private func screenPoint(for event: NSEvent) -> CGPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    private func finishResize(cancelled: Bool, point: CGPoint? = nil) {
        guard var session = resizeSession else { return }
        let size = session.end(at: point ?? NSEvent.mouseLocation, cancelled: cancelled)
        resizeSession = nil
        onResizeChanged?(size)
        if settings.iconSize != size { settings.iconSize = size }
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

/// Event routing stays on DockView; this view only establishes correct glass content.
@MainActor private final class DockIconSurface: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Measured from 2x screenshots of the macOS 26 system Dock and DogBar on the same wallpaper.
/// Clear glass lifts the backdrop toward grey (wallpaper 98,24,64 became 105,42,75), while the
/// system Dock keeps its hue and saturation (109,26,71). Its rim is a ~0.5 pt additive line
/// (+85…110 per channel) with a fainter line inside it, bright along the top and bottom and
/// fading to nothing halfway down the sides. Its indicators are additive beads (+120…140).
enum DockGlassStyle {
    static let rimWidth: CGFloat = 0.5
    static let rimAlpha: CGFloat = 0.5
    static let innerRimAlpha: CGFloat = 0.2
    static let separatorAlpha: CGFloat = 0.22
    static let indicator = NSColor.white.withAlphaComponent(0.5)
    /// Opacity of a fully saturated layer in saturation blend mode. It keeps the glass's own
    /// hue and luminance but raises its saturation, and leaves neutral greys untouched.
    static let darkVibrance: Float = 0.25
    static let lightVibrance: Float = 0.2

    /// Rim brightness from the top edge (1) to the middle of the sides, mirrored at the bottom.
    /// Stops are in points, as measured around the system Dock's corners, so tall side Docks
    /// fade the same way instead of keeping a bright rim far down their long edges.
    static func rimProfile(length: CGFloat) -> (locations: [CGFloat], weights: [CGFloat]) {
        let stops: [(CGFloat, CGFloat)] = [(0, 1), (3, 0.5), (7.5, 0.32), (16, 0.2), (26, 0.1)]
        guard length > 0 else { return ([0, 1], [1, 1]) }
        let half = length / 2
        var top = stops.filter { $0.0 < half }.map { ($0.0 / length, $0.1) }
        top.append((0.5, half > 30 ? 0.03 : stops.last { $0.0 < half }?.1 ?? 1))
        let bottom = top.dropLast().reversed().map { (1 - $0.0, $0.1) }
        let all = top + bottom
        return (all.map(\.0), all.map(\.1))
    }

    /// macOS app icon artwork fills 824 of 1024 px, centred, with a 185.4 px corner radius.
    static let iconArtworkInset: CGFloat = 100 / 1024
    static let iconArtworkCorner: CGFloat = 185.4 / 824

    /// The material minus each icon's artwork (not its padded tile), so saturation lifts the glass
    /// right up to the icon edge without boosting the icon itself or leaving a duller square around it.
    static func vibrancePath(material: CGRect, radius: CGFloat, icons: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        guard !material.isEmpty else { return path }
        let r = max(0, min(radius, min(material.width, material.height) / 2))
        path.addRoundedRect(in: material, cornerWidth: r, cornerHeight: r)
        for icon in icons {
            let artwork = icon.insetBy(dx: icon.width * iconArtworkInset, dy: icon.height * iconArtworkInset)
            let hole = artwork.intersection(material)
            guard !hole.isNull, !hole.isEmpty else { continue }
            let corner = min(min(artwork.width, artwork.height) * iconArtworkCorner, min(hole.width, hole.height) / 2)
            path.addRoundedRect(in: hole, cornerWidth: corner, cornerHeight: corner)
        }
        return path
    }
}
