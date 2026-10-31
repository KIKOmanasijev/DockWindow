import AppKit
import SwiftUI

@MainActor final class PreviewPresentation: ObservableObject {
    @Published var contentID: UInt64 = 0
    @Published var app: TrackedApp?
    @Published var bundleURL: URL?
    @Published var appName = "Application"
    @Published var appIcon: NSImage?
    @Published var windows: [TrackedWindow] = []
    @Published var thumbnailSize = CGSize(width: 288, height: 180)
    @Published var size = CGSize(width: 340, height: 260)
    @Published var message: String?
    @Published var opening = false
    @Published var resourceUsage: AppResourceUsage?
    @Published var resourceUsageUnavailable = false
    @Published var desktopLabels: [CGWindowID: String] = [:]
    @Published var edge: DockPosition = .bottom
    @Published var pointerOffset: CGFloat = 0
    var activate: (TrackedWindow) -> Void = { _ in }
    var close: (TrackedWindow) -> Void = { _ in }
    var minimize: (TrackedWindow) -> Void = { _ in }
    var zoom: (TrackedWindow) -> Void = { _ in }
    var open: () -> Void = {}
    var visibility: (CGWindowID, Bool) -> Void = { _, _ in }
}

/// Preview surface using the shared overlay cards and service cache.
@MainActor struct PreviewView: View {
    @ObservedObject var presentation: PreviewPresentation
    @ObservedObject var settings: AppSettings
    @ObservedObject var thumbnails: ThumbnailService
    var body: some View {
        let _ = thumbnails.revision
        VStack(alignment: .leading, spacing: 10) {
            // The app is named once here; the cards below show only what tells windows apart.
            HStack(spacing: 8) {
                if let icon = presentation.appIcon { Image(nsImage: icon).resizable().scaledToFit().frame(width: 22, height: 22) }
                Text(presentation.appName).font(.system(size: 13, weight: .semibold))
                if presentation.windows.count > 1 {
                    Text("\(presentation.windows.count) windows").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if presentation.opening { ProgressView().controlSize(.small) }
            }
            if settings.previewShowCPUUsage || settings.previewShowMemoryUsage {
                Text(resourceLabel).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    .help("App-wide process totals including identifiable helpers, across all desktops. Shared memory can be counted more than once; some shared services cannot be attributed. CPU 100% is one core.")
            }
            if let message = presentation.message { Text(message).font(.callout).fixedSize(horizontal: false, vertical: true) }
            if presentation.windows.isEmpty {
                HStack(spacing: 16) {
                    if let icon = presentation.appIcon {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 64, height: 64)
                    } else { Image(systemName: "macwindow").font(.system(size: 48)).foregroundStyle(.secondary) }
                    Text(settings.previewScope == .currentDesktop ? "No open windows on this desktop" : "No open windows")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button("New Window", action: presentation.open).disabled(presentation.opening || (presentation.app == nil && presentation.bundleURL == nil))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(presentation.windows) { window in
                            WindowCardView(window: window, app: presentation.app, image: thumbnails.cachedImage(for: window.id),
                                           thumbnailSize: presentation.thumbnailSize, layout: .overlay,
                                           showTitle: settings.previewShowWindowTitles, showTrafficLights: settings.previewShowTrafficLights,
                                           reduceMotion: Theme.reducesMotion(settings), showsApp: false, activate: { presentation.activate(window) },
                                           close: { presentation.close(window) }, minimize: { presentation.minimize(window) }, zoom: { presentation.zoom(window) })
                                .overlay(alignment: .bottomLeading) {
                                    if let label = presentation.desktopLabels[window.id] {
                                        Text(label).font(.caption2).padding(6).background(.regularMaterial, in: Capsule())
                                            .padding(.leading, 14).padding(.bottom, settings.previewShowWindowTitles ? 36 : 14).allowsHitTesting(false)
                                    }
                                }
                                .onAppear { presentation.visibility(window.id, true) }
                                .onDisappear { presentation.visibility(window.id, false) }
                        }
                        if settings.previewShowNewWindowTile {
                            NewWindowPreviewTile(size: presentation.thumbnailSize, appName: presentation.appName,
                                                 opening: presentation.opening, reduceMotion: Theme.reducesMotion(settings),
                                                 action: presentation.open)
                        }
                    }.padding(3).id(presentation.contentID)
                }
            }
        }
        .padding(16).frame(width: presentation.size.width, height: presentation.size.height)
        .background(VisualEffectBackground(material: settings.panelMaterial, cornerRadius: settings.panelCornerRadius, theme: settings.theme))
        .overlay(alignment: pointerAlignment) {
            if settings.previewShowPointer {
                Image(systemName: pointerSymbol).font(.system(size: 17)).foregroundStyle(.secondary)
                    .offset(x: presentation.edge == .bottom ? presentation.pointerOffset : (presentation.edge == .left ? -8 : 8),
                            y: presentation.edge == .bottom ? 8 : presentation.pointerOffset)
                    .allowsHitTesting(false)
            }
        }
    }
    private var resourceLabel: String {
        guard let usage = presentation.resourceUsage else { return presentation.resourceUsageUnavailable ? "Usage unavailable" : "Measuring usage…" }
        var parts: [String] = []
        if settings.previewShowCPUUsage {
            parts.append(usage.cpuPercent.map { String(format: "CPU %.1f%%", $0) } ?? "CPU measuring…")
        }
        if settings.previewShowMemoryUsage {
            parts.append("RAM " + ByteCountFormatter.string(fromByteCount: Int64(clamping: usage.residentBytes), countStyle: .memory))
        }
        return parts.joined(separator: "  ")
    }
    private var pointerAlignment: Alignment { presentation.edge == .bottom ? .bottom : (presentation.edge == .left ? .leading : .trailing) }
    private var pointerSymbol: String { presentation.edge == .bottom ? "arrowtriangle.down.fill" : (presentation.edge == .left ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill") }
}

/// A nonactivating preview never steals focus from the window it previews.
@MainActor public final class PreviewPanel: NSPanel {
    public init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu; collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false; backgroundColor = .clear; hasShadow = true; hidesOnDeactivate = false
        isReleasedWhenClosed = false; animationBehavior = .none
    }
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

@MainActor private struct NewWindowPreviewTile: View {
    let size: CGSize
    let appName: String
    let opening: Bool
    let reduceMotion: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 28, weight: .medium))
                    .frame(width: 54, height: 54)
                    .background(Color.accentColor.opacity(hovered ? 0.18 : 0), in: Circle())
                Text(opening ? "Opening…" : "New Window").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(hovered ? Color.accentColor : Color.primary)
            .frame(width: size.width, height: size.height).padding(8)
            .background(hovered ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(hovered ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.10), lineWidth: hovered ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PreviewTilePressStyle(reduceMotion: reduceMotion))
        .scaleEffect(hovered && !reduceMotion && !opening ? 1.015 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }
        .disabled(opening)
        .help("Open another \(appName) window")
        .accessibilityLabel("New \(appName) window")
    }
}
private struct PreviewTilePressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
