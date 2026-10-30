import AppKit
import SwiftUI

/// Reusable traffic lights. The parent supplies service-backed operations.
@MainActor public struct TrafficLightsView: View {
    private let close: () -> Void
    private let minimize: () -> Void
    private let zoom: () -> Void
    @State private var hovered = false
    public init(close: @escaping () -> Void, minimize: @escaping () -> Void, zoom: @escaping () -> Void) {
        self.close = close; self.minimize = minimize; self.zoom = zoom
    }
    public var body: some View {
        HStack(spacing: 6) {
            light("Close window", color: .red, symbol: "xmark", action: close)
            light("Minimize window", color: .yellow, symbol: "minus", action: minimize)
            light("Toggle fullscreen", color: .green, symbol: "arrow.up.left.and.arrow.down.right", action: zoom)
        }
        .padding(7).background(.ultraThinMaterial, in: Capsule())
        .onHover { hovered = $0 }
    }
    private func light(_ label: String, color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(hovered ? color : Color.secondary.opacity(0.5))
                Image(systemName: symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(.black.opacity(0.65)).opacity(hovered ? 1 : 0)
            }.frame(width: 12, height: 12).padding(2).contentShape(Rectangle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// Glass title capsule for both header and thumbnail-overlay card layouts.
@MainActor public struct WindowTitlePill: View {
    public var app: TrackedApp?
    public var title: String
    public var showsAppName: Bool
    public init(app: TrackedApp?, title: String, showsAppName: Bool = true) {
        self.app = app; self.title = title; self.showsAppName = showsAppName
    }
    public var body: some View {
        HStack(spacing: 6) {
            if let app { Image(nsImage: app.icon).resizable().scaledToFit().frame(width: 16, height: 16) }
            VStack(alignment: .leading, spacing: 1) {
                if showsAppName { Text(app?.name ?? "Application").font(.system(size: 12, weight: .semibold)).lineLimit(1) }
                Text(title.isEmpty ? (app?.name ?? "Untitled window") : title)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 9).padding(.vertical, 5).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Shared thumbnail card, with header or preview overlay controls and no system access.
@MainActor public struct WindowCardView: View {
    public enum Layout { case header, overlay }
    private let window: TrackedWindow
    private let app: TrackedApp?
    private let image: CGImage?
    private let thumbnailSize: CGSize
    private let layout: Layout
    private let selected: Bool
    private let selectionColor: Color
    private let showTitle: Bool
    private let showTrafficLights: Bool
    private let reduceMotion: Bool
    private let select: () -> Void
    private let activate: () -> Void
    private let close: () -> Void
    private let minimize: () -> Void
    private let zoom: () -> Void
    @State private var hovered = false
    public init(window: TrackedWindow, app: TrackedApp?, image: CGImage?, thumbnailSize: CGSize,
                layout: Layout = .header, selected: Bool = false, selectionColor: Color = .accentColor,
                showTitle: Bool = true, showTrafficLights: Bool = true, reduceMotion: Bool = false,
                select: @escaping () -> Void = {}, activate: @escaping () -> Void,
                close: @escaping () -> Void, minimize: @escaping () -> Void, zoom: @escaping () -> Void) {
        self.window = window; self.app = app; self.image = image; self.thumbnailSize = thumbnailSize
        self.layout = layout; self.selected = selected; self.selectionColor = selectionColor
        self.showTitle = showTitle; self.showTrafficLights = showTrafficLights; self.reduceMotion = reduceMotion
        self.select = select; self.activate = activate; self.close = close; self.minimize = minimize; self.zoom = zoom
    }
    public var body: some View {
        VStack(spacing: 8) {
            if layout == .header { header }
            thumbnail.overlay(alignment: .top) { if layout == .overlay { header.padding(6) } }
        }
        .padding(8)
        .background(selected ? selectionColor : Color.primary.opacity(hovered ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.white.opacity(0.65) : Color.white.opacity(hovered ? 0.3 : 0.08), lineWidth: selected ? 2.5 : 1))
        .scaleEffect(hovered && !reduceMotion ? 1.02 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .onHover { value in hovered = value; if value { select() } }
    }
    private var header: some View {
        HStack(spacing: 6) {
            if showTrafficLights { TrafficLightsView(close: close, minimize: minimize, zoom: zoom) }
            if showTitle {
                Button(action: activate) { WindowTitlePill(app: app, title: window.title) }.buttonStyle(.plain)
            }
        }.frame(height: 40)
    }
    private var thumbnail: some View {
        Button(action: activate) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else if let app {
                    Image(nsImage: app.icon).resizable().scaledToFit().frame(width: 72, height: 72)
                } else { Image(systemName: "macwindow").font(.system(size: 48)).foregroundStyle(.secondary) }
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .opacity(window.isMinimized || window.isAppHidden ? 0.55 : 1)
            .overlay(alignment: .bottomTrailing) {
                if window.isMinimized || window.isAppHidden {
                    Label(window.isMinimized ? "Minimized" : "Hidden", systemImage: window.isMinimized ? "minus.square" : "eye.slash")
                        .font(.caption2).padding(6).background(.regularMaterial, in: Capsule()).padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Focus \(window.title)")
    }
}
