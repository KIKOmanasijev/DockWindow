import AppKit

/// One icon with separately animated window indicators and native-style badge.
@MainActor final class DockIconLayer: CALayer {
    let imageLayer = CALayer()
    let dots = CAShapeLayer()
    let badge = CATextLayer()
    private var cachedImage: NSImage?
    private var lastIndicators = DotIndicators(count: 0)
    override init() {
        super.init()
        addSublayer(imageLayer); addSublayer(dots); addSublayer(badge)
        imageLayer.contentsGravity = .resizeAspect
        badge.fontSize = 11; badge.alignmentMode = .center; badge.foregroundColor = NSColor.white.cgColor
        badge.backgroundColor = NSColor.systemRed.cgColor; badge.cornerRadius = 9
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { nil }
    func update(image: NSImage?, badgeText: String?, indicators: DotIndicators, color: NSColor,
                position: DockPosition, scale: CGFloat, reduceMotion: Bool) {
        if reduceMotion { dots.removeAllAnimations() }
        imageLayer.frame = bounds
        if let image, image !== cachedImage {
            imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil); cachedImage = image
        }
        imageLayer.contentsScale = scale
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
    func bounce(position: DockPosition, enabled: Bool) {
        guard enabled else { imageLayer.removeAnimation(forKey: "launch"); return }
        guard imageLayer.animation(forKey: "launch") == nil else { return }
        let animation = CAKeyframeAnimation(keyPath: position == .bottom ? "transform.translation.y" : "transform.translation.x")
        let sign: CGFloat = position == .right ? -1 : 1
        animation.values = [0, 22 * sign, 0, 10 * sign, 0]
        animation.keyTimes = [0, 0.3, 0.55, 0.8, 1]; animation.duration = 0.85; animation.repeatCount = .infinity
        imageLayer.add(animation, forKey: "launch")
    }
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
