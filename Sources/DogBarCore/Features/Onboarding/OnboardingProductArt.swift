import AppKit
import SwiftUI

// Native recreations of the landing page's Mac scenes: the same app icons, wallpapers and
// window thumbnails, drawn with SwiftUI so they stay sharp and can react to the tour.

struct AppIconImage: View {
    let name: String
    var size: CGFloat
    var body: some View {
        Group {
            if let image = OnboardingAssets.app(name) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(Color.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
    }
}

struct WallpaperImage: View {
    let name: String
    var body: some View {
        if let image = OnboardingAssets.wallpaper(name) {
            Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [Color(hex: 0x9FB4E6), Color(hex: 0xC9B8FF)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The landing page's CSS window thumbnails: a title bar with traffic lights and a hint of content.
struct WindowThumb: View {
    enum Kind { case trip, booking, slack, notes, music }
    let kind: Kind
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            // CSS background-position: a percentage aligns that point of the layer with the same point of the box.
            func bar(_ color: Color, _ bw: Double, _ bh: Double, _ px: Double, _ py: Double) {
                let rect = CGRect(x: (w - w * bw) * px, y: (h - h * bh) * py, width: w * bw, height: h * bh)
                context.fill(Path(rect), with: .color(color))
            }
            let soft = Color(hex: 0xCBC4DA), dim = Color(hex: 0x5C5378)
            switch kind {
            case .trip:
                let rect = CGRect(x: (w - w * 0.84) * 0.5, y: (h - h * 0.44) * 0.36, width: w * 0.84, height: h * 0.44)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(stops: [.init(color: Color(hex: 0xFFD08A), location: 0), .init(color: Color(hex: 0xFF8F7A), location: 0.58),
                                     .init(color: Color(hex: 0x7B4BD8), location: 0.585), .init(color: Color(hex: 0x7B4BD8), location: 1)]),
                    startPoint: CGPoint(x: rect.midX - rect.width * 0.09, y: rect.minY), endPoint: CGPoint(x: rect.midX + rect.width * 0.09, y: rect.maxY)))
                bar(dim, 0.64, 0.07, 0.08, 0.78); bar(soft, 0.5, 0.05, 0.08, 0.92)
            case .booking:
                bar(Color(hex: 0x5A1BC4), 0.24, 0.05, 0.10, 0.24); bar(OnboardingPalette.ink, 0.5, 0.08, 0.5, 0.42)
                bar(Color(hex: 0xE6E0F0), 0.64, 0.10, 0.5, 0.64); bar(OnboardingPalette.purple, 0.64, 0.12, 0.5, 0.86)
            case .slack:
                bar(Color(hex: 0x2BAC76), 0.08, 0.11, 0.44, 0.70); bar(Color(hex: 0xE8912D), 0.08, 0.11, 0.44, 0.38)
                bar(soft, 0.38, 0.05, 0.86, 0.72); bar(soft, 0.46, 0.05, 0.92, 0.42); bar(Color(hex: 0x4A154B), 0.32, 1, 0, 0)
            case .notes:
                bar(soft, 0.58, 0.05, 0.22, 0.82); bar(soft, 0.52, 0.05, 0.20, 0.66); bar(soft, 0.60, 0.05, 0.22, 0.50); bar(dim, 0.52, 0.08, 0.14, 0.28)
            case .music:
                bar(soft, 0.36, 0.06, 0.64, 0.82); bar(soft, 0.44, 0.06, 0.74, 0.56); bar(dim, 0.40, 0.07, 0.70, 0.28)
                bar(Color(hex: 0xFFB020), 0.14, 0.16, 0.10, 0.82); bar(OnboardingPalette.purple, 0.14, 0.16, 0.10, 0.56); bar(Color(hex: 0xFF6B8B), 0.14, 0.16, 0.10, 0.30)
            }
            // Title bar on top, as the CSS ::before layer is.
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.14)), with: .color(titleBar))
            for (x, hex) in [(0.09, 0xFF5F57), (0.16, 0xFEBC2E), (0.23, 0x28C840)] as [(Double, UInt32)] {
                let r = w * 0.03
                context.fill(Path(ellipseIn: CGRect(x: w * x - r, y: h * 0.07 - r, width: r * 2, height: r * 2)), with: .color(Color(hex: hex)))
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    private var background: Color {
        switch kind { case .booking: Color(hex: 0xFAF8FF); case .notes: Color(hex: 0xFFFBEA); default: .white }
    }
    private var titleBar: Color {
        switch kind { case .slack: Color(hex: 0x3F0E40); case .notes: Color(hex: 0xFBF3D2); default: Color(hex: 0xF1EEF6) }
    }
}

/// DogBar's Dock at any icon size: one slot per app, one dot per window, a divider before Trash.
struct MiniDock: View {
    struct Item: Hashable { var app: String; var windows: Int }
    let items: [Item]
    var iconSize: CGFloat
    var highlighted: String? = nil
    var body: some View {
        let u = iconSize / 48
        HStack(alignment: .top, spacing: 4 * u) {
            ForEach(items, id: \.self) { item in
                VStack(spacing: 2 * u) {
                    AppIconImage(name: item.app, size: iconSize * 0.805)
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: .black.opacity(0.22), radius: 1 * u, y: 0.75 * u)
                        .brightness(highlighted == item.app ? -0.12 : 0)
                    HStack(spacing: max(1.5, 2.5 * u)) {
                        ForEach(0..<min(item.windows, 5), id: \.self) { _ in
                            Circle().fill(Color.black.opacity(0.62)).frame(width: max(3, 4.5 * u), height: max(3, 4.5 * u))
                        }
                    }
                    .frame(height: max(3, 4.5 * u))
                }
            }
            Rectangle().fill(Color.white.opacity(0.55)).frame(width: 1, height: iconSize * 0.72).padding(.top, iconSize * 0.14)
            AppIconImage(name: "trash", size: iconSize).frame(width: iconSize, height: iconSize)
        }
        .padding(.top, 8.5 * u).padding(.horizontal, 8 * u).padding(.bottom, 9 * u)
        .background {
            let shape = RoundedRectangle(cornerRadius: 0.3 * iconSize, style: .continuous)
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08), .white.opacity(0.16)], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.12), .white.opacity(0.3)], startPoint: .leading, endPoint: .trailing), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.16), radius: 9 * u, y: 5 * u)
                .environment(\.colorScheme, .light)
        }
    }
}

struct PointerCursor: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 5, y: 3.5)); path.addLine(to: CGPoint(x: 19, y: 12))
            path.addLine(to: CGPoint(x: 12.6, y: 13.4)); path.addLine(to: CGPoint(x: 9.6, y: 20)); path.closeSubpath()
        }
        .fill(OnboardingPalette.ink)
        .overlay(Path { path in
            path.move(to: CGPoint(x: 5, y: 3.5)); path.addLine(to: CGPoint(x: 19, y: 12))
            path.addLine(to: CGPoint(x: 12.6, y: 13.4)); path.addLine(to: CGPoint(x: 9.6, y: 20)); path.closeSubpath()
        }.stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
    }
}

/// A small frosted label on a wallpaper, like the landing page's desktop names.
struct StageTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(OnboardingPalette.ink)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.78)))
    }
}

/// The rounded frame every product scene sits in.
struct StageFrame<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(width: 480, height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5).padding(-0.5))
            .shadow(color: Color(hex: 0x10062E).opacity(0.28), radius: 24, y: 14)
    }
}

/// Plays a short, single-purpose sequence once per step visit. Cancelled when the step leaves,
/// and skipped entirely with Reduce Motion, which shows the final state instead.
@MainActor enum SceneSequence {
    static func run(reduceMotion: Bool, steps: [(delay: Double, action: @MainActor () -> Void)]) async {
        if reduceMotion { for step in steps { step.action() }; return }
        for step in steps {
            try? await Task.sleep(for: .milliseconds(Int(step.delay * 1000)))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step.action() }
        }
    }
}

// MARK: - A Dock per desktop

struct DesktopsScene: View {
    let reduceMotion: Bool
    @State private var desktop = 1
    @State private var userChose = false
    private let work: [MiniDock.Item] = [.init(app: "finder", windows: 0), .init(app: "slack", windows: 2), .init(app: "figma", windows: 1),
                                         .init(app: "calendar", windows: 1), .init(app: "notes", windows: 1), .init(app: "mail", windows: 1)]
    private let personal: [MiniDock.Item] = [.init(app: "finder", windows: 0), .init(app: "chrome", windows: 2), .init(app: "tv", windows: 1),
                                             .init(app: "music", windows: 1), .init(app: "photos", windows: 1), .init(app: "messages", windows: 1)]
    var body: some View {
        VStack(spacing: 14) {
            StageFrame {
                ZStack {
                    if desktop == 1 { screen(wall: "tahoe", name: "Desktop 1 · Work", window: .slack, items: work).transition(slide(edge: .leading)) }
                    else { screen(wall: "sequoia-blue", name: "Desktop 2 · Personal", window: .music, items: personal).transition(slide(edge: .trailing)) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(desktop == 1
                ? "Desktop 1, Work. Its Dock shows Finder, Slack, Figma, Calendar, Notes and Mail, then Trash."
                : "Desktop 2, Personal. Its Dock shows Finder, Chrome, TV, Music, Photos and Messages, then Trash.")
            Picker("Desktop", selection: Binding(get: { desktop }, set: { value in
                userChose = true
                withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.88)) { desktop = value }
            })) {
                Text("Desktop 1").tag(1)
                Text("Desktop 2").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            .accessibilityLabel("Show desktop")
        }
        .task {
            // One swipe to show the idea, then the picker is the user's. Reduce Motion stays on Desktop 1.
            guard !reduceMotion else { return }
            await SceneSequence.run(reduceMotion: reduceMotion, steps: [(1.6, { if !userChose { desktop = 2 } })])
        }
    }
    private func slide(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: edge == .leading ? .leading : .trailing),
                                              removal: .move(edge: edge == .leading ? .leading : .trailing))
    }
    private func screen(wall: String, name: String, window: WindowThumb.Kind, items: [MiniDock.Item]) -> some View {
        ZStack {
            WallpaperImage(name: wall).frame(width: 480, height: 340).clipped()
            VStack {
                HStack { StageTag(text: name); Spacer() }.padding(14)
                Spacer()
                WindowThumb(kind: window).frame(width: 250)
                    .shadow(color: Color(hex: 0x10062E).opacity(0.4), radius: 14, y: 10)
                Spacer()
                MiniDock(items: items, iconSize: 40).padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Previews and exact-window actions

struct PreviewsScene: View {
    let reduceMotion: Bool
    @State private var pointerOnSafari = false
    @State private var popoverShown = false
    @State private var chosen = false
    @State private var picked = false
    @State private var replay = 0
    private let items: [MiniDock.Item] = [.init(app: "finder", windows: 0), .init(app: "safari", windows: 2),
                                          .init(app: "slack", windows: 1), .init(app: "notes", windows: 3)]
    var body: some View {
        VStack(spacing: 14) {
            StageFrame {
                ZStack(alignment: .bottom) {
                    WallpaperImage(name: "sequoia").frame(width: 480, height: 340).clipped()
                    if picked {
                        VStack(spacing: 6) {
                            WindowThumb(kind: .booking).frame(width: 230)
                                .shadow(color: Color(hex: 0x10062E).opacity(0.4), radius: 14, y: 10)
                            StageTag(text: "Hotel booking comes forward")
                        }
                        .frame(maxHeight: .infinity, alignment: .center).padding(.bottom, 40)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    }
                    VStack(spacing: 10) {
                        if popoverShown {
                            popover.transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                        }
                        MiniDock(items: items, iconSize: 46, highlighted: pointerOnSafari ? "safari" : nil)
                            .overlay(alignment: .topLeading) {
                                PointerCursor()
                                    .offset(x: pointerOnSafari ? 82 : 150, y: pointerOnSafari ? 26 : 60)
                                    .opacity(picked ? 0 : 1)
                            }
                    }
                    .padding(.bottom, 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The pointer rests on Safari in the Dock. A preview shows its two windows, Lisbon day plan and Hotel booking. Choosing Hotel booking brings just that window forward.")
            Button { replay += 1 } label: { Label("Play Again", systemImage: "arrow.counterclockwise") }
                .buttonStyle(OnboardingQuietButtonStyle())
                .opacity(reduceMotion ? 0 : 1).disabled(reduceMotion)
                .accessibilityHidden(reduceMotion)
        }
        .task(id: replay) {
            pointerOnSafari = false; popoverShown = false; chosen = false; picked = false
            await SceneSequence.run(reduceMotion: reduceMotion, steps: [
                (0.6, { pointerOnSafari = true }), (0.45, { popoverShown = true }), (1.2, { chosen = true }),
                (0.9, { popoverShown = false; picked = true }),
            ])
        }
    }
    private var popover: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                AppIconImage(name: "safari", size: 15)
                Text("Safari").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.85))
                Text("2 windows").font(.system(size: 12)).foregroundStyle(.black.opacity(0.5))
            }
            HStack(spacing: 6) {
                card(.trip, "Lisbon day plan", on: false)
                card(.booking, "Hotel booking", on: chosen)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color(hex: 0xF6F6F8, opacity: 0.6)))
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
                .environment(\.colorScheme, .light)
        }
    }
    private func card(_ kind: WindowThumb.Kind, _ title: String, on: Bool) -> some View {
        VStack(spacing: 4) {
            WindowThumb(kind: kind).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.85)).lineLimit(1)
        }
        .padding(5).frame(width: 120)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(on ? 0.1 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(OnboardingPalette.purple.opacity(on ? 0.7 : 0), lineWidth: 1.5))
    }
}

// MARK: - Window switcher

struct SwitcherScene: View {
    let reduceMotion: Bool
    let shortcut: String
    @State private var selected = 0
    @State private var tabPulse = false
    @State private var replay = 0
    private let tiles: [(WindowThumb.Kind, String, String)] = [(.trip, "safari", "Lisbon day plan"), (.booking, "safari", "Hotel booking"),
                                                               (.slack, "slack", "#lisbon-trip"), (.notes, "notes", "Packing list")]
    var body: some View {
        VStack(spacing: 14) {
            StageFrame {
                ZStack {
                    WallpaperImage(name: "sonoma").frame(width: 480, height: 340).clipped()
                    Color.black.opacity(0.12)
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text("macOS ⌘Tab · one icon per app").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                            HStack(spacing: 8) { ForEach(["safari", "slack", "notes"], id: \.self) { AppIconImage(name: $0, size: 30) } }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x1E182C, opacity: 0.75)))
                        }
                        .opacity(0.85)
                        VStack(spacing: 6) {
                            Text("DogBar · one tile per window").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            HStack(spacing: 6) {
                                ForEach(tiles.indices, id: \.self) { index in tile(index) }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x1E182C, opacity: 0.92)))
                            .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
                        }
                        HStack(spacing: 6) {
                            Text(shortcut).font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(OnboardingPalette.ink)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(tabPulse ? 1 : 0.82)))
                                .scaleEffect(tabPulse ? 0.94 : 1)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("macOS Command Tab shows one icon each for Safari, Slack and Notes. DogBar's switcher shows four window tiles: Lisbon day plan and Hotel booking from Safari, lisbon-trip from Slack and Packing list from Notes. The shortcut is \(shortcut).")
            Button { replay += 1 } label: { Label("Play Again", systemImage: "arrow.counterclockwise") }
                .buttonStyle(OnboardingQuietButtonStyle())
                .opacity(reduceMotion ? 0 : 1).disabled(reduceMotion)
                .accessibilityHidden(reduceMotion)
        }
        .task(id: replay) {
            selected = 0; tabPulse = false
            await SceneSequence.run(reduceMotion: reduceMotion, steps: [
                (0.9, { tabPulse = true }), (0.12, { tabPulse = false; selected = 1 }),
                (0.9, { tabPulse = true }), (0.12, { tabPulse = false; selected = 2 }),
                (0.7, { tabPulse = true }), (0.12, { tabPulse = false; selected = 1 }),
            ])
        }
    }
    private func tile(_ index: Int) -> some View {
        let (kind, app, name) = tiles[index]
        let on = selected == index
        return VStack(spacing: 3) {
            WindowThumb(kind: kind)
            AppIconImage(name: app, size: 24).padding(.top, -16).shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            Text(name).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color(hex: 0xF3F0FA)).lineLimit(1)
        }
        .padding(6).frame(width: 96)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(on ? 0.16 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(on ? 0.6 : 0), lineWidth: 1.5))
    }
}

// MARK: - Permissions

/// A simplified System Settings privacy list with DogBar's row. The switch mirrors the real,
/// live permission check; nothing here changes the setting itself.
struct PermissionPanel: View {
    let pane: String
    let granted: Bool
    let uses: [String]
    let never: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(pane).font(.system(size: 13, weight: .semibold))
                }
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 26, height: 26)
                    Text("DogBar").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Capsule().fill(granted ? Color(nsColor: .controlAccentColor) : Color.secondary.opacity(0.28))
                        .frame(width: 38, height: 22)
                        .overlay(alignment: granted ? .trailing : .leading) {
                            Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: granted)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OnboardingPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OnboardingPalette.line))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("System Settings, \(pane). DogBar's switch is \(granted ? "on" : "off").")

            VStack(alignment: .leading, spacing: 9) {
                Text("DogBar uses it to").font(.system(size: 12, weight: .semibold)).foregroundStyle(OnboardingPalette.muted)
                ForEach(uses, id: \.self) { use in
                    Label { Text(use) } icon: { Image(systemName: "checkmark").foregroundStyle(OnboardingPalette.success) }
                        .font(.system(size: 13.5))
                }
                Label { Text(never) } icon: { Image(systemName: "hand.raised").foregroundStyle(OnboardingPalette.accent) }
                    .font(.system(size: 13.5)).padding(.top, 4)
            }
            .foregroundStyle(OnboardingPalette.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 400)
    }
}
