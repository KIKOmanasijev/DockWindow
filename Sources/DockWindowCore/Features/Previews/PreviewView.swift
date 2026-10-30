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
            HStack {
                if let icon = presentation.appIcon { Image(nsImage: icon).resizable().scaledToFit().frame(width: 24, height: 24) }
                Text(presentation.appName).font(.system(size: 14, weight: .semibold))
                Spacer()
                if presentation.opening { ProgressView().controlSize(.small) }
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
                                           reduceMotion: Theme.reducesMotion(settings), activate: { presentation.activate(window) },
                                           close: { presentation.close(window) }, minimize: { presentation.minimize(window) }, zoom: { presentation.zoom(window) })
                                .overlay(alignment: .bottomLeading) {
                                    if let label = presentation.desktopLabels[window.id] {
                                        Text(label).font(.caption2).padding(6).background(.regularMaterial, in: Capsule()).padding(14).allowsHitTesting(false)
                                    }
                                }
                                .onAppear { presentation.visibility(window.id, true) }
                                .onDisappear { presentation.visibility(window.id, false) }
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
