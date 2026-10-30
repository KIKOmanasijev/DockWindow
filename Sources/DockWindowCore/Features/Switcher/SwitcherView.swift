import AppKit
import SwiftUI

@MainActor final class SwitcherPresentation: ObservableObject {
    @Published var session = SwitcherSession()
    @Published var apps: [TrackedApp] = []
    @Published var columns = 1
    @Published var thumbnailSize = CGSize(width: 320, height: 200)
    var tileSize: CGSize { SwitcherTileMetrics.size(thumbnail: thumbnailSize) }
    @Published var size = CGSize(width: 360, height: 280)
    @Published var revealed = false
    @Published var message: String?
    var select: (SwitcherTileID) -> Void = { _ in }
    var activate: (SwitcherTileID) -> Void = { _ in }
    var operate: (TrackedWindow, SwitcherCommand) -> Void = { _, _ in }
    var zoom: (TrackedWindow) -> Void = { _ in }
    var visibility: (CGWindowID, Bool) -> Void = { _, _ in }
    var dismiss: () -> Void = {}
}

@MainActor struct SwitcherView: View {
    @ObservedObject var presentation: SwitcherPresentation
    @ObservedObject var settings: AppSettings
    @ObservedObject var thumbnails: ThumbnailService
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if let message = presentation.message {
                    VStack(spacing: 12) {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                        Button("Dismiss", action: presentation.dismiss).buttonStyle(.bordered)
                    }.padding(24)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(presentation.tileSize.width), spacing: 12), count: presentation.columns), spacing: 12) {
                    ForEach(presentation.session.items, id: \.tileID) { item in
                        tile(item).fixedSize().scaleEffect(SwitcherTileMetrics.scale)
                            .frame(width: presentation.tileSize.width, height: presentation.tileSize.height)
                            .id(item.tileID)
                    }
                }.padding(20)
            }
            .onChange(of: presentation.session.selectedID) { _, value in
                guard let value else { return }
                withAnimation(Theme.reducesMotion(settings) ? nil : .easeOut(duration: 0.1)) { proxy.scrollTo(value, anchor: .center) }
            }
            .onChange(of: presentation.revealed) { _, revealed in
                if revealed, let id = presentation.session.selectedID { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(width: presentation.size.width, height: presentation.size.height)
        .background(VisualEffectBackground(material: settings.panelMaterial, cornerRadius: settings.panelCornerRadius, theme: settings.theme))
        .clipShape(RoundedRectangle(cornerRadius: settings.panelCornerRadius))
        .opacity(presentation.revealed ? 1 : 0)
        .scaleEffect(presentation.revealed || Theme.reducesMotion(settings) ? 1 : 0.98)
        .animation(Theme.reducesMotion(settings) ? nil : .easeOut(duration: 0.12), value: presentation.revealed)
        .preferredColorScheme(settings.theme == .system ? nil : settings.theme == .dark ? .dark : .light)
    }
    @ViewBuilder private func tile(_ item: SwitcherItem) -> some View {
        switch item {
        case .window(let window):
            WindowCardView(window: window, app: presentation.apps.first { $0.pid == window.pid }, image: thumbnails.cachedImage(for: window.id),
                           thumbnailSize: presentation.thumbnailSize, selected: presentation.session.selectedID == item.tileID,
                           selectionColor: Theme.selection(settings), reduceMotion: Theme.reducesMotion(settings),
                           select: { presentation.select(item.tileID) }, activate: { presentation.activate(item.tileID) },
                           close: { presentation.operate(window, .closeWindow) }, minimize: { presentation.operate(window, .minimizeWindow) }, zoom: { presentation.zoom(window) })
                .onAppear { presentation.visibility(window.id, true) }
                .onDisappear { presentation.visibility(window.id, false) }
        case .windowlessApp(let app):
            Button { presentation.activate(item.tileID) } label: {
                VStack(spacing: 8) {
                    WindowTitlePill(app: app, title: "No Open Windows").frame(height: 40)
                    VStack(spacing: 12) {
                        Image(nsImage: app.icon).resizable().scaledToFit().frame(width: 80, height: 80)
                        Text("No Open Windows").font(.callout).italic().foregroundStyle(.secondary)
                    }.frame(width: presentation.thumbnailSize.width, height: presentation.thumbnailSize.height)
                }.padding(8)
                    .background(presentation.session.selectedID == item.tileID ? Theme.selection(settings) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(presentation.session.selectedID == item.tileID ? 0.65 : 0.08), lineWidth: presentation.session.selectedID == item.tileID ? 2.5 : 1))
            }.buttonStyle(.plain).onHover { if $0 { presentation.select(item.tileID) } }
        }
    }
}
