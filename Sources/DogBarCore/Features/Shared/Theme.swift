import AppKit
import SwiftUI

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
        highlight.colors = [NSColor.white.withAlphaComponent(0.15).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
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
@available(macOS 26.0, *)
@MainActor public struct GlassDockBackgroundProvider: DockBackgroundProvider {
    public init() {}
    public func makeBackgroundView() -> NSView { NSGlassEffectView() }
    public func updateBackgroundView(_ view: NSView, material: PanelMaterial, cornerRadius: CGFloat, theme: AppTheme) {
        guard let glass = view as? NSGlassEffectView else { return }
        glass.cornerRadius = max(0, cornerRadius); glass.appearance = Theme.appearance(theme)
    }
}
#endif

/// Chooses true glass only when both the build SDK and running OS support it.
@MainActor public enum DockBackgroundProviders {
    public static func preferred() -> any DockBackgroundProvider {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return GlassDockBackgroundProvider() }
        #endif
        return MaterialDockBackgroundProvider()
    }
}
