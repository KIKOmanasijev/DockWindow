import AppKit

/// One icon with separately animated window indicators and native-style badge.
@MainActor final class DockIconLayer: CALayer {
    let imageLayer = CALayer()
    /// Darkens the icon's own shape while it is pressed, like the system Dock.
    let shade = CALayer()
    private let shadeMask = CALayer()
    let dots = CAShapeLayer()
    let badge = CATextLayer()
    private var cachedImage: NSImage?
    private var cachedPixelSize = CGSize.zero
    private var lastIndicators = DotIndicators(count: 0)
    override init() {
        super.init()
        addSublayer(imageLayer); addSublayer(dots); addSublayer(badge)
        imageLayer.addSublayer(shade)
        // The raster already matches the layer's pixel size, so no resampling filter applies.
        imageLayer.contentsGravity = .center
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .nearest
        shade.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        shade.mask = shadeMask; shade.isHidden = true
        shadeMask.contentsGravity = .center
        badge.fontSize = 11; badge.alignmentMode = .center; badge.foregroundColor = NSColor.white.cgColor
        badge.backgroundColor = NSColor.systemRed.cgColor; badge.cornerRadius = 9
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { nil }
    func update(image: NSImage?, badgeText: String?, indicators: DotIndicators, color: NSColor,
                position: DockPosition, scale: CGFloat, reduceMotion: Bool) {
        if reduceMotion { dots.removeAllAnimations() }
        imageLayer.frame = bounds
        shade.frame = imageLayer.bounds; shadeMask.frame = shade.bounds
        let pixels = DockIconRasterizer.pixelSize(size: bounds.size, scale: scale)
        if let image, image !== cachedImage || cachedPixelSize != pixels {
            let raster = DockIconRasterizer.render(image, size: bounds.size, scale: scale)
            imageLayer.contents = raster; shadeMask.contents = raster
            cachedImage = image; cachedPixelSize = pixels
        } else if image == nil {
            imageLayer.contents = nil; shadeMask.contents = nil; cachedImage = nil; cachedPixelSize = .zero
        }
        imageLayer.contentsScale = scale; shadeMask.contentsScale = scale
        let text = badgeText ?? ""
        badge.isHidden = text.isEmpty; badge.string = text
        let width = max(18, (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width + 10)
        badge.frame = CGRect(x: bounds.maxX - width + 2, y: bounds.maxY - 17, width: width, height: 18)
        badge.contentsScale = scale
        let path = CGMutablePath()
        let diameter = max(2, min(5, bounds.width / 12))
        let stride = diameter + 3
        for index in 0..<indicators.count {
            let offset = (CGFloat(index) - CGFloat(indicators.count - 1) / 2) * stride
            let center: CGPoint
            switch position {
            case .bottom: center = CGPoint(x: bounds.midX + offset, y: -5)
            case .left: center = CGPoint(x: -5, y: bounds.midY + offset)
            case .right: center = CGPoint(x: bounds.maxX + 5, y: bounds.midY + offset)
            }
            path.addEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        }
        if indicators != lastIndicators, lastIndicators.count > 0, !reduceMotion {
            let outgoing = CAShapeLayer()
            outgoing.path = dots.path; outgoing.fillColor = dots.fillColor; outgoing.strokeColor = dots.strokeColor
            outgoing.lineWidth = dots.lineWidth; addSublayer(outgoing)
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.15
            outgoing.opacity = 0; outgoing.add(fade, forKey: "out")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { outgoing.removeFromSuperlayer() }
        }
        dots.path = path; dots.fillColor = indicators.isHollow ? NSColor.clear.cgColor : color.cgColor
        dots.strokeColor = indicators.isHollow ? color.cgColor : NSColor.clear.cgColor; dots.lineWidth = 1
        if indicators != lastIndicators, !reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.15
            dots.add(fade, forKey: "count")
        }
        lastIndicators = indicators
    }
    func setPressed(_ pressed: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shade.isHidden = !pressed
        CATransaction.commit()
    }
    func bounce(position: DockPosition, enabled: Bool, reduceMotion: Bool = false) {
        let keyPath = position == .bottom ? "transform.translation.y" : "transform.translation.x"
        guard enabled, !reduceMotion else {
            guard imageLayer.animation(forKey: "launch") != nil else {
                if reduceMotion { imageLayer.removeAnimation(forKey: "launch-settle") }
                return
            }
            let transform = imageLayer.presentation()?.transform ?? CATransform3DIdentity
            let offset = position == .bottom ? transform.m42 : transform.m41
            imageLayer.removeAnimation(forKey: "launch")
            // Finish gently when the process is ready, rather than snapping down mid-jump.
            if !reduceMotion, abs(offset) > 0.1 {
                let settle = CABasicAnimation(keyPath: keyPath)
                settle.fromValue = offset; settle.toValue = 0; settle.duration = 0.18
                settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
                imageLayer.add(settle, forKey: "launch-settle")
            }
            return
        }
        guard imageLayer.animation(forKey: "launch") == nil else { return }
        imageLayer.removeAnimation(forKey: "launch-settle")
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        let sign: CGFloat = position == .right ? -1 : 1
        // One consistent jump and a short rest; no alternating large/fast, small/slow cycles.
        animation.values = [0, 16 * sign, 0, 0]
        animation.keyTimes = [0, 0.4, 0.8, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                     CAMediaTimingFunction(name: .easeIn),
                                     CAMediaTimingFunction(name: .linear)]
        animation.duration = 1.25; animation.repeatCount = .infinity
        imageLayer.add(animation, forKey: "launch")
    }

}

/// Draws the best NSImage representation at the actual display pixel size, including Retina.
@MainActor enum DockIconRasterizer {
    static func pixelSize(size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(1, ceil(size.width * max(1, scale))), height: max(1, ceil(size.height * max(1, scale))))
    }
    static func render(_ image: NSImage, size: CGSize, scale: CGFloat) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let pixels = pixelSize(size: size, scale: scale)
        guard let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphics
        // Draw in pixel units and pick the representation for the real pixel size (icons
        // carry sizes up to 1024 px). Choosing by point size picks a 1x image and blurs it.
        let target = CGRect(origin: .zero, size: pixels)
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high.rawValue]
        if let rep = image.bestRepresentation(for: target, context: graphics, hints: nil) {
            rep.draw(in: target, from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: hints)
        } else {
            image.draw(in: target, from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: hints)
        }
        return context.makeImage()
    }
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
}

/// A nonactivating panel which cannot steal the active application's key window.
@MainActor final class DockPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        hidesOnDeactivate = false; acceptsMouseMovedEvents = true; ignoresMouseEvents = true
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
