import AppKit
import SwiftUI
import Combine

/// Shared appearance conversions for switcher and preview surfaces.
@MainActor public enum Theme {
    public static func selection(_ settings: AppSettings) -> Color {
        settings.useCustomSelectionColor ? color(settings.selectionColor) : Color(nsColor: .controlAccentColor)
    }
    public static func color(_ value: SettingsColor) -> Color {
        Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
    public static func appearance(_ theme: AppTheme) -> NSAppearance? {
        switch theme {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    public static func material(_ material: PanelMaterial) -> NSVisualEffectView.Material {
        switch material {
        case .hudWindow: return .hudWindow
        case .popover: return .popover
        case .sidebar: return .sidebar
        case .menu: return .menu
        }
    }
    public static func reducesMotion(_ settings: AppSettings) -> Bool {
        settings.reduceAnimations || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Rounded blurred backing shared by floating panels. Appearance updates live.
@MainActor public struct VisualEffectBackground: NSViewRepresentable {
    public var material: PanelMaterial
    public var cornerRadius: CGFloat
    public var theme: AppTheme
    public init(material: PanelMaterial = .hudWindow, cornerRadius: CGFloat = 26, theme: AppTheme = .system) {
        self.material = material; self.cornerRadius = cornerRadius; self.theme = theme
    }
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow; view.state = .active; view.wantsLayer = true
        return view
    }
    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = Theme.material(material); view.appearance = Theme.appearance(theme)
        view.layer?.cornerRadius = max(0, cornerRadius); view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }
}

/// AppKit Dock backing abstraction, independent of the Dock's layout engine.
@MainActor public protocol DockBackgroundProvider {
    func makeBackgroundView() -> NSView
    func updateBackgroundView(_ view: NSView, material: PanelMaterial, cornerRadius: CGFloat, theme: AppTheme)
}

/// SDK-compatible glass approximation with material, inner stroke and top highlight.
@MainActor public struct MaterialDockBackgroundProvider: DockBackgroundProvider {
    public init() {}
    public func makeBackgroundView() -> NSView { DockMaterialView() }
    public func updateBackgroundView(_ view: NSView, material: PanelMaterial, cornerRadius: CGFloat, theme: AppTheme) {
        guard let view = view as? DockMaterialView else { return }
        view.effect.material = Theme.material(material); view.appearance = Theme.appearance(theme)
        view.effect.layer?.cornerRadius = max(0, cornerRadius)
        view.effect.layer?.masksToBounds = true
        view.highlight.cornerRadius = max(0, cornerRadius)
        view.shadow = NSShadow()
        view.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.25)
        view.shadow?.shadowBlurRadius = 10; view.shadow?.shadowOffset = NSSize(width: 0, height: -3)
    }
}

@MainActor private final class DockMaterialView: NSView {
    let effect = NSVisualEffectView()
    let highlight = CAGradientLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        effect.blendingMode = .behindWindow; effect.state = .active; effect.wantsLayer = true
        effect.layer?.borderWidth = 0.5; effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        addSubview(effect)
        highlight.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        highlight.locations = [0, 0.45]; highlight.masksToBounds = true
        highlight.startPoint = CGPoint(x: 0.5, y: 1); highlight.endPoint = CGPoint(x: 0.5, y: 0)
        effect.layer?.addSublayer(highlight)
    }
    required init?(coder: NSCoder) { nil }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Resize the actual material in the same drag event, not the next layout pass.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effect.frame = bounds; highlight.frame = effect.bounds
        CATransaction.commit()
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effect.frame = bounds; highlight.frame = effect.bounds
        CATransaction.commit()
    }
}

#if compiler(>=6.2)
/// Native Liquid Glass backing when built with a macOS 26 or newer SDK.
@MainActor public struct GlassDockBackgroundProvider: DockBackgroundProvider {
    public init() {}
    public func makeBackgroundView() -> NSView { NSGlassEffectView() }
    public func updateBackgroundView(_ view: NSView, material: PanelMaterial, cornerRadius: CGFloat, theme: AppTheme) {
        guard let glass = view as? NSGlassEffectView else { return }
        glass.style = .clear
        glass.tintColor = NSColor.black.withAlphaComponent(0.035)
        glass.cornerRadius = max(0, cornerRadius); glass.appearance = Theme.appearance(theme)
    }
}
#endif

/// Uses Apple's public Liquid Glass view when the build SDK predates its Swift
/// declarations. No private selectors are used.
@MainActor public struct RuntimeGlassDockBackgroundProvider: DockBackgroundProvider {
    public init() {}
    public func makeBackgroundView() -> NSView {
        guard let type = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
            return MaterialDockBackgroundProvider().makeBackgroundView()
        }
        let view = type.init(frame: .zero)
        // Public NSGlassEffectView.Style.clear (1) keeps wallpaper colour visible.
        if view.responds(to: NSSelectorFromString("setStyle:")) { view.setValue(1, forKey: "style") }
        return view
    }
    public func updateBackgroundView(_ view: NSView, material: PanelMaterial, cornerRadius: CGFloat, theme: AppTheme) {
        guard view.isKind(of: NSClassFromString("NSGlassEffectView") ?? NSView.self),
              view.responds(to: NSSelectorFromString("setCornerRadius:")) else {
            MaterialDockBackgroundProvider().updateBackgroundView(view, material: material, cornerRadius: cornerRadius, theme: theme)
            return
        }
        view.setValue(cornerRadius, forKey: "cornerRadius")
        if view.responds(to: NSSelectorFromString("setTintColor:")) {
            view.setValue(NSColor.black.withAlphaComponent(0.035), forKey: "tintColor")
        }
        view.appearance = Theme.appearance(theme)
    }
}

@MainActor public enum DockBackgroundProviders {
    /// DogBar requires macOS 26, so the Dock always uses Liquid Glass: the typed view with
    /// a macOS 26 SDK, otherwise the same public class looked up at runtime. The material
    /// approximation remains only as that lookup's fallback.
    public static func preferred() -> any DockBackgroundProvider {
        #if compiler(>=6.2)
        return GlassDockBackgroundProvider()
        #else
        return RuntimeGlassDockBackgroundProvider()
        #endif
    }
}

/// Shared edge treatment for every clear-glass surface.
@MainActor final class GlassRim {
    private let reflection = CAGradientLayer()
    private let mask = CAShapeLayer()
    private let outer = CAShapeLayer()
    init(darkEdge: Bool = true) {
        reflection.colors = [NSColor.white.withAlphaComponent(0.58).cgColor,
                             NSColor.white.withAlphaComponent(0.08).cgColor,
                             (darkEdge ? NSColor.black.withAlphaComponent(0.16) : NSColor.white.withAlphaComponent(0.08)).cgColor,
                             NSColor.white.withAlphaComponent(0.42).cgColor]
        reflection.locations = [0, 0.3, 0.7, 1]
        reflection.startPoint = CGPoint(x: 0.5, y: 1)
        reflection.endPoint = CGPoint(x: 0.5, y: 0)
        mask.fillColor = nil; mask.strokeColor = NSColor.white.cgColor; mask.lineWidth = 1
        reflection.mask = mask
        outer.fillColor = nil; outer.strokeColor = NSColor.black.withAlphaComponent(0.22).cgColor
        outer.lineWidth = 0.5; outer.isHidden = !darkEdge
        outer.zPosition = 9; reflection.zPosition = 10
    }
    func attach(to layer: CALayer?) {
        layer?.addSublayer(outer); layer?.addSublayer(reflection)
    }
    func update(frame: CGRect, cornerRadius: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        reflection.frame = frame; outer.frame = frame; mask.frame = reflection.bounds
        let outerRadius = max(0, cornerRadius - 0.25), innerRadius = max(0, cornerRadius - 1)
        outer.path = CGPath(roundedRect: outer.bounds.insetBy(dx: 0.25, dy: 0.25),
                            cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)
        mask.path = CGPath(roundedRect: reflection.bounds.insetBy(dx: 1, dy: 1),
                           cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil)
        CATransaction.commit()
    }
}

/// Glass owns the hosting view so its backdrop never samples the panel's own
/// thumbnails. Both floating panels use the same content/layout lifecycle.
@MainActor final class GlassPanelHost<Content: View>: NSView {
    private let provider = DockBackgroundProviders.preferred()
    private let glass: NSView
    private let hosting: NSHostingView<Content>
    private let rim = GlassRim(darkEdge: false)
    private let settings: AppSettings
    private var subscription: AnyCancellable?
    init(rootView: Content, settings: AppSettings) {
        self.settings = settings
        glass = provider.makeBackgroundView()
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(glass)
        rim.attach(to: layer)
        hosting.autoresizingMask = [.width, .height]
        if glass.responds(to: NSSelectorFromString("setContentView:")) {
            glass.setValue(hosting, forKey: "contentView")
        } else { glass.addSubview(hosting) }
        updateAppearance()
        subscription = settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updateAppearance() }
    }
    required init?(coder: NSCoder) { nil }
    private func updateAppearance() {
        provider.updateBackgroundView(glass, material: settings.panelMaterial,
                                      cornerRadius: settings.panelCornerRadius, theme: settings.theme)
        rim.update(frame: bounds, cornerRadius: settings.panelCornerRadius)
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glass.frame = bounds
        hosting.frame = glass.bounds
        rim.update(frame: bounds, cornerRadius: settings.panelCornerRadius)
        CATransaction.commit()
    }
}
