import AppKit
import SwiftUI

// Native versions of the landing page's Mac scenes: the same macOS wallpapers and app icons,
// with real glass. Every glass surface shows a blurred, saturated copy of the exact wallpaper
// behind it (not a generic material), a soft tint, and the landing page's specular rim.

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
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [Color(hex: 0x9FB4E6), Color(hex: 0xC9B8FF)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Glass

/// The wallpaper and size of the scene a glass surface sits on.
struct StageContext { var wallpaper: String; var size: CGSize; var space: String }
private struct StageContextKey: EnvironmentKey { static let defaultValue: StageContext? = nil }
extension EnvironmentValues {
    var stage: StageContext? {
        get { self[StageContextKey.self] }
        set { self[StageContextKey.self] = newValue }
    }
}

/// The part of the stage's wallpaper behind this view, blurred and lifted like Liquid Glass.
struct WallpaperGlass: View {
    var blur: CGFloat
    @Environment(\.stage) private var stage
    var body: some View {
        GeometryReader { proxy in
            if let stage {
                let frame = proxy.frame(in: .named(stage.space))
                WallpaperImage(name: stage.wallpaper)
                    .frame(width: stage.size.width, height: stage.size.height).clipped()
                    .saturation(1.7).brightness(0.05)
                    .blur(radius: blur, opaque: true)
                    .offset(x: -frame.minX, y: -frame.minY)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
}

enum GlassStyle {
    /// The Dock: clear glass, the wallpaper stays in view.
    case clear
    /// The Dock preview panel: a light frosted HUD.
    case light
    /// The window switcher: a dark frosted HUD.
    case dark
}

extension View {
    func glass<S: InsettableShape>(_ shape: S, style: GlassStyle = .clear, shadow: CGFloat = 1) -> some View {
        let blur: CGFloat = style == .clear ? 7 : 22
        let fill: [Color] = switch style {
        case .clear: [.white.opacity(0.24), .white.opacity(0.08), .white.opacity(0.16)]
        case .light: [Color(hex: 0xF6F6F8, opacity: 0.74), Color(hex: 0xF6F6F8, opacity: 0.66)]
        case .dark: [Color(hex: 0x1E182C, opacity: 0.66), Color(hex: 0x1E182C, opacity: 0.78)]
        }
        let rim: [Color] = style == .dark
            ? [.white.opacity(0.38), .white.opacity(0.06), .white.opacity(0.2)]
            : [.white.opacity(0.8), .white.opacity(0.14), .white.opacity(0.45)]
        return background {
            WallpaperGlass(blur: blur)
                .clipShape(shape)
                .overlay(shape.fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom)))
                // Inner light along the top edge, as a lens would catch it.
                .overlay(shape.inset(by: 1.5).stroke(LinearGradient(colors: [.white.opacity(style == .dark ? 0.12 : 0.4), .clear], startPoint: .top, endPoint: .center), lineWidth: 2).blur(radius: 1.2))
                // Specular rim, brightest towards the ends.
                .overlay(shape.strokeBorder(LinearGradient(colors: rim, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: .black.opacity(0.2 * shadow), radius: 16 * shadow, y: 9 * shadow)
        }
    }
}

/// A wallpaper scene whose glass surfaces blur that same wallpaper.
struct Stage<Content: View>: View {
    let wallpaper: String
    let size: CGSize
    var radius: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        let space = "stage.\(wallpaper).\(Int(size.width))"
        ZStack {
            WallpaperImage(name: wallpaper).frame(width: size.width, height: size.height).clipped()
            content
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(.named(space))
        .environment(\.stage, StageContext(wallpaper: wallpaper, size: size, space: space))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The landing page's feature card: a white frame around the scene, a hairline and a soft lift.
struct SceneCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(OnboardingPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(OnboardingPalette.line))
            .shadow(color: Color(hex: 0x2B0A74).opacity(0.12), radius: 30, y: 18)
    }
}

// MARK: - Mac parts

/// The landing page's window thumbnails: a title bar with traffic lights and a hint of content.
struct WindowThumb: View {
    enum Kind { case trip, booking, slack, notes, music }
    let kind: Kind
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            // CSS background-position: a percentage aligns that point of the layer with the same point of the box.
            func bar(_ color: Color, _ bw: Double, _ bh: Double, _ px: Double, _ py: Double, radius: Double = 0) {
                let rect = CGRect(x: (w - w * bw) * px, y: (h - h * bh) * py, width: w * bw, height: h * bh)
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
            }
            let soft = Color(hex: 0xCBC4DA), dim = Color(hex: 0x5C5378), r = h * 0.02
            switch kind {
            case .trip:
                let rect = CGRect(x: (w - w * 0.84) * 0.5, y: (h - h * 0.44) * 0.36, width: w * 0.84, height: h * 0.44)
                context.fill(Path(roundedRect: rect, cornerRadius: r), with: .linearGradient(
                    Gradient(stops: [.init(color: Color(hex: 0xFFD08A), location: 0), .init(color: Color(hex: 0xFF8F7A), location: 0.58),
                                     .init(color: Color(hex: 0x7B4BD8), location: 0.585), .init(color: Color(hex: 0x7B4BD8), location: 1)]),
                    startPoint: CGPoint(x: rect.midX - rect.width * 0.09, y: rect.minY), endPoint: CGPoint(x: rect.midX + rect.width * 0.09, y: rect.maxY)))
                bar(dim, 0.64, 0.07, 0.08, 0.78, radius: r); bar(soft, 0.5, 0.05, 0.08, 0.92, radius: r)
            case .booking:
                bar(Color(hex: 0x5A1BC4), 0.24, 0.05, 0.10, 0.24, radius: r); bar(OnboardingPalette.ink, 0.5, 0.08, 0.5, 0.42, radius: r)
                bar(Color(hex: 0xE6E0F0), 0.64, 0.10, 0.5, 0.64, radius: r); bar(OnboardingPalette.purple, 0.64, 0.12, 0.5, 0.86, radius: r * 2)
            case .slack:
                bar(Color(hex: 0x4A154B), 0.32, 1, 0, 0)
                bar(Color(hex: 0x2BAC76), 0.08, 0.11, 0.44, 0.70, radius: r); bar(Color(hex: 0xE8912D), 0.08, 0.11, 0.44, 0.38, radius: r)
                bar(soft, 0.38, 0.05, 0.86, 0.72, radius: r); bar(soft, 0.46, 0.05, 0.92, 0.42, radius: r)
            case .notes:
                bar(dim, 0.52, 0.08, 0.14, 0.28, radius: r)
                bar(soft, 0.60, 0.05, 0.22, 0.50, radius: r); bar(soft, 0.52, 0.05, 0.20, 0.66, radius: r); bar(soft, 0.58, 0.05, 0.22, 0.82, radius: r)
            case .music:
                bar(Color(hex: 0xFF6B8B), 0.14, 0.16, 0.10, 0.30, radius: r * 2); bar(OnboardingPalette.purple, 0.14, 0.16, 0.10, 0.56, radius: r * 2)
                bar(Color(hex: 0xFFB020), 0.14, 0.16, 0.10, 0.82, radius: r * 2)
                bar(dim, 0.40, 0.07, 0.70, 0.28, radius: r); bar(soft, 0.44, 0.06, 0.74, 0.56, radius: r); bar(soft, 0.36, 0.06, 0.64, 0.82, radius: r)
            }
            // Title bar on top.
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.14)), with: .color(titleBar))
            for (x, hex) in [(0.09, 0xFF5F57), (0.16, 0xFEBC2E), (0.23, 0x28C840)] as [(Double, UInt32)] {
                let radius = w * 0.028
                context.fill(Path(ellipseIn: CGRect(x: w * x - radius, y: h * 0.07 - radius, width: radius * 2, height: radius * 2)), with: .color(Color(hex: hex)))
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
    }
    private var background: Color {
        switch kind { case .booking: Color(hex: 0xFAF8FF); case .notes: Color(hex: 0xFFFBEA); default: .white }
    }
    private var titleBar: Color {
        switch kind { case .slack: Color(hex: 0x3F0E40); case .notes: Color(hex: 0xFBF3D2); default: Color(hex: 0xF1EEF6) }
    }
}

/// A window floating on a desktop, with the macOS window shadow.
struct FloatingWindow: View {
    let kind: WindowThumb.Kind
    var width: CGFloat
    var body: some View {
        WindowThumb(kind: kind).frame(width: width)
            .shadow(color: Color(hex: 0x10062E).opacity(0.18), radius: 2, y: 1)
            .shadow(color: Color(hex: 0x10062E).opacity(0.38), radius: width * 0.08, y: width * 0.06)
    }
}

/// DogBar's Dock at any icon size, in clear glass over the stage's wallpaper: one dot per
/// window, a divider before Trash. With `revealed` false the icons are hidden, so a scene can
/// bring them in one by one.
struct MiniDock: View {
    struct Item: Hashable { var app: String; var windows: Int }
    let items: [Item]
    var iconSize: CGFloat
    var highlighted: String? = nil
    var revealed = true
    var reduceMotion = false
    /// Publishes each icon as a mascot target named "dock.<app>".
    var targets = false
    /// An icon pressed in by the mascot.
    var pressed: String? = nil
    /// Apps shown dimmed, like DogBar's apps from other desktops. Used by Settings.
    var dimmed: Set<String> = []
    var showsTrash = true
    var body: some View {
        let u = iconSize / 48
        HStack(alignment: .top, spacing: 4 * u) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                VStack(spacing: 2.5 * u) {
                    AppIconImage(name: item.app, size: iconSize * 0.805)
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: .black.opacity(0.22), radius: 1 * u, y: 0.75 * u)
                        .brightness(highlighted == item.app ? -0.18 : 0)
                        .scaleEffect(pressed == item.app ? 0.9 : 1)
                        .modifier(TargetIf(enabled: targets, id: "dock.\(item.app)"))
                    HStack(spacing: max(1.2, 2.5 * u)) {
                        ForEach(0..<min(item.windows, 5), id: \.self) { _ in
                            Circle().fill(Color.black.opacity(0.7)).frame(width: max(2, 4 * u), height: max(2, 4 * u))
                        }
                    }
                    .frame(height: max(2, 4 * u))
                }
                .saturation(dimmed.contains(item.app) ? 0.2 : 1)
                .scaleEffect(revealed ? 1 : 0.5, anchor: .bottom)
                .opacity(revealed ? (dimmed.contains(item.app) ? 0.45 : 1) : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.7).delay(revealed ? Double(index) * 0.05 : 0), value: revealed)
            }
            if showsTrash {
                Rectangle().fill(Color.white.opacity(0.5)).frame(width: max(0.75, u), height: iconSize * 0.7).padding(.top, iconSize * 0.15)
                AppIconImage(name: "trash", size: iconSize).frame(width: iconSize, height: iconSize)
            }
        }
        .padding(.top, 8.5 * u).padding(.horizontal, 8 * u).padding(.bottom, 8 * u)
        .glass(RoundedRectangle(cornerRadius: 0.3 * iconSize, style: .continuous), shadow: max(0.4, u))
    }
}

private struct TargetIf: ViewModifier {
    let enabled: Bool
    let id: String
    func body(content: Content) -> some View {
        if enabled { content.mascotTarget(id) } else { content }
    }
}

struct PointerCursor: View {
    var body: some View {
        let shape = Path { path in
            path.move(to: CGPoint(x: 5, y: 3.5)); path.addLine(to: CGPoint(x: 19, y: 12))
            path.addLine(to: CGPoint(x: 12.6, y: 13.4)); path.addLine(to: CGPoint(x: 9.6, y: 20)); path.closeSubpath()
        }
        shape.fill(OnboardingPalette.ink)
            .overlay(shape.stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
    }
}

/// A small frosted label on a wallpaper, like the landing page's desktop names.
struct StageTag: View {
    let text: String
    var size: CGFloat = 11.5
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(OnboardingPalette.ink)
            .padding(.horizontal, size * 0.75).padding(.vertical, size * 0.28)
            .background(Capsule().fill(Color.white.opacity(0.8)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

/// Plays a short, single-purpose sequence once per step visit. Cancelled when the step leaves.
/// With Reduce Motion it applies every change at once, showing the final state.
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

struct ReplayButton: View {
    let reduceMotion: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label("Play Again", systemImage: "arrow.counterclockwise") }
            .buttonStyle(OnboardingQuietButtonStyle())
            .opacity(reduceMotion ? 0 : 1).disabled(reduceMotion)
            .accessibilityHidden(reduceMotion)
    }
}

// MARK: - A Dock per desktop

/// Two desktops in Mac bezels. Each Dock fills with only that desktop's apps as it becomes
/// the active one, then the swipe moves to the other desktop. Click a desktop to switch.
struct DesktopsScene: View {
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var active = 0
    @State private var revealed = [false, false]
    @State private var replay = 0
    @StateObject private var dog = MascotDirector(MascotState(frame: .celebrate))
    private let screen = CGSize(width: 226, height: 160)
    private let dogSize: CGFloat = 136
    /// Desktop centres from the card's leading edge.
    private let deskCenters: [CGFloat] = [151, 393]
    private let desks: [(wall: String, name: String, window: WindowThumb.Kind, items: [MiniDock.Item])] = [
        ("tahoe", "Desktop 1 · Work", .slack, [.init(app: "finder", windows: 0), .init(app: "slack", windows: 2), .init(app: "figma", windows: 1),
                                               .init(app: "calendar", windows: 1), .init(app: "notes", windows: 1), .init(app: "mail", windows: 1)]),
        ("sequoia-blue", "Desktop 2 · Personal", .music, [.init(app: "finder", windows: 0), .init(app: "chrome", windows: 2), .init(app: "tv", windows: 1),
                                                         .init(app: "music", windows: 1), .init(app: "photos", windows: 1), .init(app: "messages", windows: 1)]),
    ]
    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
            SceneCard {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        desk(0)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(OnboardingPalette.purple)
                            .rotationEffect(.degrees(active == 1 ? 0 : 180))
                            .accessibilityHidden(true)
                        desk(1)
                    }
                }
                .padding(.vertical, 26).padding(.horizontal, 14)
                .frame(width: 520)
                .background(backdrop)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            // The dog peeks over the card's top edge, paws resting on it, above the active desktop.
            MascotRigView(dog: dog, size: dogSize, peek: true)
                .offset(x: deskCenters[0] - dogSize / 2, y: -dogSize * MascotRig.peekEdge - MascotRig.rimClearance)
            }
            .padding(.top, 66)
            ReplayButton(reduceMotion: reduceMotion) { replay += 1 }
        }
        .task(id: replay) {
            dog.reduceMotion = reduceMotion
            active = 0; revealed = reduceMotion ? [true, true] : [false, false]
            let hidden = -dogSize * 0.56, travel = deskCenters[1] - deskCenters[0]
            dog.set(nil) { $0 = MascotState(frame: .celebrate, lift: reduceMotion ? 0 : hidden) }
            guard !reduceMotion else { return }
            await dog.perform {
                guard await dog.beat(0.35) else { return }
                // Slowly rises from behind the card and settles its paws on the edge.
                dog.set(.spring(response: 0.95, dampingFraction: 0.82)) { $0.lift = 0 }
                guard await dog.beat(0.75) else { return }
                withAnimation { revealed[0] = true }
                await dog.blink()
                guard await dog.beat(0.6) else { return }
                // Ducks, slides along the edge to Desktop 2 and pops up there as it becomes active.
                dog.set(.easeIn(duration: 0.18)) { $0.lift = -dogSize * 0.16 }
                guard await dog.beat(0.16) else { return }
                dog.set(.easeInOut(duration: 0.55)) { $0.x = travel }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { active = 1 }
                guard await dog.beat(0.5) else { return }
                dog.set(.spring(response: 0.4, dampingFraction: 0.6)) { $0.lift = 0 }
                withAnimation { revealed[1] = true }
                guard await dog.beat(0.35) else { return }
                await dog.pose(.wave)
                await dog.wave(2)
                await dog.blink()
            }
        }
    }

    private var backdrop: some View {
        let dark = colorScheme == .dark
        return ZStack {
            LinearGradient(colors: dark ? [Color(hex: 0x2A1B57), Color(hex: 0x1D1438), Color(hex: 0x2E1630)]
                                        : [Color(hex: 0xDDD0FF), Color(hex: 0xF1EAFF), Color(hex: 0xFFE6EE)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(dark ? 0.06 : 0.7), .clear], center: .init(x: 0.15, y: 0.15), startRadius: 4, endRadius: 260)
        }
    }

    private func desk(_ index: Int) -> some View {
        let desk = desks[index]
        let isActive = active == index
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) { active = index; revealed[index] = true }
            dog.set(.spring(response: 0.55, dampingFraction: 0.8)) { $0.x = deskCenters[index] - deskCenters[0]; $0.lift = 0 }
        } label: {
            Stage(wallpaper: desk.wall, size: screen, radius: 9) {
                VStack(spacing: 0) {
                    HStack { StageTag(text: desk.name, size: 9); Spacer() }.padding(8)
                    Spacer(minLength: 0)
                    FloatingWindow(kind: desk.window, width: 118)
                    Spacer(minLength: 0)
                    MiniDock(items: desk.items, iconSize: 21, revealed: revealed[index], reduceMotion: reduceMotion).padding(.bottom, 6)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color(hex: 0x0E0C13)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1).padding(-1))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(OnboardingPalette.purple.opacity(isActive ? 0.9 : 0), lineWidth: 2).padding(-4))
            .shadow(color: Color(hex: 0x14043C).opacity(isActive ? 0.45 : 0.25), radius: isActive ? 18 : 10, y: isActive ? 12 : 6)
            .scaleEffect(isActive ? 1 : 0.95)
            .opacity(isActive ? 1 : 0.82)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(desk.name). Its Dock shows \(desk.items.map(\.app).joined(separator: ", ")), then Trash.")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Previews and exact-window actions

/// One take, cause before effect: the pointer hovers Safari in the Dock and its preview opens,
/// travels to Hotel booking, clicks it, the preview closes, and only then does Hotel booking come
/// in front of Lisbon day plan. It then holds that frame until Play Again. The dog watches from
/// the corner and cheers after the click.
struct PreviewsScene: View {
    let reduceMotion: Bool
    private enum Pointer { case start, safari, booking }
    @State private var pointer = Pointer.start
    @State private var safariHovered = false
    @State private var previewShown = false
    @State private var bookingHovered = false
    @State private var pressing = false
    @State private var rippleShown = false
    @State private var rippleDone = false
    @State private var bookingFront = false
    /// Target frames in the stage, kept after the preview closes so the pointer stays where it clicked.
    @State private var frames: [String: CGRect] = [:]
    @State private var replay = 0
    @StateObject private var dog = MascotDirector(MascotState(frame: .guide))
    private let dogSize: CGFloat = 112
    private let size = CGSize(width: 500, height: 350)
    private let items: [MiniDock.Item] = [.init(app: "finder", windows: 0), .init(app: "safari", windows: 2),
                                          .init(app: "slack", windows: 1), .init(app: "notes", windows: 3)]

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                SceneCard {
                    Stage(wallpaper: "sequoia", size: size) { screen }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hovering Safari in the Dock opens a preview of its two windows, Lisbon day plan and Hotel booking. Clicking Hotel booking closes the preview and brings only that window in front of Lisbon day plan.")
                MascotRigView(dog: dog, size: dogSize)
                    .offset(x: -dogSize * 0.62, y: dogSize * 0.1)
            }
            ReplayButton(reduceMotion: reduceMotion) { replay += 1 }
        }
        .task(id: replay) { await play() }
    }

    private var screen: some View {
        ZStack {
            // Two Safari windows. Lisbon day plan starts in front; Hotel booking only comes forward after the click.
            ZStack {
                FloatingWindow(kind: .booking, width: 224).offset(x: 62, y: -44)
                    .scaleEffect(bookingFront ? 1 : 0.985)
                    .zIndex(bookingFront ? 2 : 0)
                FloatingWindow(kind: .trip, width: 214).offset(x: -66, y: -62)
                    .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 10) {
                Spacer()
                if previewShown {
                    preview.transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                }
                MiniDock(items: items, iconSize: 44, highlighted: safariHovered ? "safari" : nil, targets: true)
                    .padding(.bottom, 12)
            }
            if reduceMotion {
                VStack { StageTag(text: "Click a preview to bring just that window forward"); Spacer() }.padding(.top, 14)
            }
        }
        .frame(width: size.width, height: size.height)
        .backgroundPreferenceValue(MascotTargets.self) { targets in
            GeometryReader { proxy in
                ForEach(Array(targets.keys), id: \.self) { id in
                    if let anchor = targets[id] {
                        Color.clear.onChange(of: proxy[anchor], initial: true) { _, rect in frames[id] = rect }
                    }
                }
            }
        }
        .overlay { pointerLayer }
    }

    @ViewBuilder private var pointerLayer: some View {
        if let tip = pointerTip {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 2.5)
                    .background(Circle().fill(Color.white.opacity(0.25)))
                    .frame(width: 34, height: 34)
                    .scaleEffect(rippleDone ? 1.7 : 0.4)
                    .opacity(rippleShown ? (rippleDone ? 0 : 0.95) : 0)
                    .position(tip)
                // The arrow's hotspot is its tip, at (5, 3.5) in its 24 pt frame.
                PointerCursor()
                    .scaleEffect(pressing ? 0.84 : 1, anchor: UnitPoint(x: 5 / 24, y: 3.5 / 24))
                    .position(x: tip.x + 7, y: tip.y + 8.5)
            }
            .allowsHitTesting(false)
        }
    }

    private var pointerTip: CGPoint? {
        switch pointer {
        case .start: return CGPoint(x: size.width * 0.8, y: size.height * 0.56)
        case .safari: return frames["dock.safari"].map { CGPoint(x: $0.midX + 4, y: $0.midY + 2) }
        case .booking: return frames["tile.booking"].map { CGPoint(x: $0.midX + 6, y: $0.midY - 4) }
        }
    }

    private func play() async {
        dog.reduceMotion = reduceMotion
        // Every replay starts from the same frame.
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) {
            pointer = .start; safariHovered = false; previewShown = false; bookingHovered = false
            pressing = false; rippleShown = false; rippleDone = false; bookingFront = false
        }
        dog.set(nil) { $0 = MascotState(frame: .guide, opacity: reduceMotion ? 1 : 0) }
        if reduceMotion {
            // A still that explains the choice: the preview open, Hotel booking highlighted under the pointer.
            previewShown = true; safariHovered = true; bookingHovered = true
            try? await Task.sleep(for: .milliseconds(50))
            pointer = .booking
            return
        }
        await dog.perform {
            func wait(_ seconds: Double) async -> Bool { await dog.beat(seconds) }
            guard await wait(0.35) else { return }
            dog.set(.easeOut(duration: 0.35)) { $0.opacity = 1 }
            // 1. The pointer travels to Safari in the Dock and rests there.
            withAnimation(.easeInOut(duration: 0.8)) { pointer = .safari }
            guard await wait(0.8) else { return }
            withAnimation(.easeOut(duration: 0.12)) { safariHovered = true }
            guard await wait(0.45) else { return }
            // 2. Hovering opens the preview.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { previewShown = true }
            await dog.blink()
            guard await wait(0.45) else { return }
            // 3. The pointer travels to Hotel booking; only that tile highlights.
            guard frames["tile.booking"] != nil else { return }
            withAnimation(.easeInOut(duration: 0.65)) { pointer = .booking }
            guard await wait(0.65) else { return }
            withAnimation(.easeOut(duration: 0.12)) { bookingHovered = true }
            guard await wait(0.45) else { return }
            // 4. Click: the pointer presses and a ripple marks the spot.
            withAnimation(.easeOut(duration: 0.08)) { pressing = true; rippleShown = true }
            withAnimation(.easeOut(duration: 0.5)) { rippleDone = true }
            guard await wait(0.13) else { return }
            withAnimation(.easeOut(duration: 0.1)) { pressing = false }
            guard await wait(0.15) else { return }
            // 5. The preview closes, then only Hotel booking comes forward. Lisbon stays behind.
            withAnimation(.easeIn(duration: 0.2)) { previewShown = false; safariHovered = false }
            guard await wait(0.28) else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.7)) { bookingFront = true }
            guard await wait(0.3) else { return }
            // The dog cheers, then the frame holds until Play Again.
            await dog.pose(.celebrate)
            await dog.hop(14)
            await dog.wag(2)
            guard await wait(0.25) else { return }
            await dog.pose(.guide)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                AppIconImage(name: "safari", size: 16)
                Text("Safari").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.black.opacity(0.85))
                Text("2 windows").font(.system(size: 12.5)).foregroundStyle(.black.opacity(0.5))
            }
            HStack(spacing: 7) {
                tile(.trip, "Lisbon day plan", hovered: false)
                tile(.booking, "Hotel booking", hovered: bookingHovered).mascotTarget("tile.booking")
            }
        }
        .padding(11)
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous), style: .light)
    }
    private func tile(_ kind: WindowThumb.Kind, _ title: String, hovered: Bool) -> some View {
        VStack(spacing: 5) {
            WindowThumb(kind: kind)
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.black.opacity(0.85)).lineLimit(1)
        }
        .padding(6).frame(width: 128)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(hovered ? 0.11 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(hovered ? OnboardingPalette.purple.opacity(0.75) : Color.white.opacity(0.1), lineWidth: hovered ? 1.5 : 1))
        .scaleEffect(hovered && pressing ? 0.97 : 1)
    }
}

// MARK: - Window switcher

/// Hold the modifier, tap Tab: the switcher opens with one tile per window and the selection walks across them.
struct SwitcherScene: View {
    let reduceMotion: Bool
    let shortcut: KeyboardShortcut
    @State private var panelShown = false
    @State private var selected = 0
    @State private var keyDown = false
    @State private var replay = 0
    @StateObject private var dog = MascotDirector(MascotState(frame: .guide, mirrored: true))
    private let dogSize: CGFloat = 118
    private let size = CGSize(width: 500, height: 350)
    private let tiles: [(WindowThumb.Kind, String, String)] = [(.trip, "safari", "Lisbon day plan"), (.booking, "safari", "Hotel booking"),
                                                               (.slack, "slack", "#lisbon-trip"), (.notes, "notes", "Packing list")]
    var body: some View {
        VStack(spacing: 12) {
            SceneCard {
                Stage(wallpaper: "sonoma", size: size) {
                    ZStack {
                        FloatingWindow(kind: .notes, width: 190).offset(x: -120, y: -70)
                        FloatingWindow(kind: .trip, width: 210).offset(x: 110, y: -40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 18) {
                        Spacer()
                        if panelShown {
                            panel.transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
                        }
                        keys
                        Spacer().frame(height: 22)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Holding \(keyNames) opens DogBar's switcher with one tile per window: Lisbon day plan and Hotel booking from Safari, lisbon-trip from Slack and Packing list from Notes. Each tap of Tab moves to the next window.")
            ReplayButton(reduceMotion: reduceMotion) { replay += 1 }
        }
        // The dog, facing left, presses Tab for each step through the windows.
        .overlayPreferenceValue(MascotTargets.self) { targets in
            GeometryReader { proxy in
                if let anchor = targets["key.tab"] {
                    let key = proxy[anchor]
                    MascotRigView(dog: dog, size: dogSize)
                        .position(MascotRigView.center(touching: CGPoint(x: key.maxX - key.width * 0.12, y: key.midY - key.height * 0.1),
                                                       size: dogSize, mirrored: true))
                }
            }
        }
        .task(id: replay) {
            dog.reduceMotion = reduceMotion
            panelShown = false; selected = 0; keyDown = false
            dog.set(nil) { $0 = MascotState(frame: .guide, x: reduceMotion ? 0 : 60, mirrored: true, opacity: reduceMotion ? 1 : 0) }
            if reduceMotion { panelShown = true; selected = 2; return }
            await dog.perform {
                guard await dog.beat(0.25) else { return }
                dog.set(.easeOut(duration: 0.25)) { $0.opacity = 1 }
                dog.set(.spring(response: 0.5, dampingFraction: 0.8)) { $0.x = 0 }
                await dog.hop(10)
                await dog.blink()
                for index in 0..<3 {
                    // Each press: the dog leans onto Tab, the key goes down, the selection moves.
                    withAnimation(.easeOut(duration: 0.08)) { keyDown = true }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { panelShown = true; selected = index }
                    await dog.tap(-6)
                    withAnimation(.easeOut(duration: 0.08)) { keyDown = false }
                    guard await dog.beat(index == 2 ? 0.2 : 0.45) else { return }
                }
                await dog.wag(3)
                await dog.blink()
            }
        }
    }
    private var panel: some View {
        HStack(spacing: 6) {
            ForEach(tiles.indices, id: \.self) { index in tile(index) }
        }
        .padding(10)
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous), style: .dark)
    }
    private func tile(_ index: Int) -> some View {
        let (kind, app, name) = tiles[index]
        let on = selected == index
        return VStack(spacing: 3) {
            WindowThumb(kind: kind)
            AppIconImage(name: app, size: 26).padding(.top, -17).shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            Text(name).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color(hex: 0xF3F0FA)).lineLimit(1)
        }
        .padding(6).frame(width: 104)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(on ? 0.18 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(on ? 0.65 : 0), lineWidth: 1.5))
    }

    private var keyCaps: [(symbol: String, word: String, isKey: Bool)] {
        var caps: [(String, String, Bool)] = []
        if shortcut.modifiers.contains(.control) { caps.append(("⌃", "control", false)) }
        if shortcut.modifiers.contains(.option) { caps.append(("⌥", "option", false)) }
        if shortcut.modifiers.contains(.shift) { caps.append(("⇧", "shift", false)) }
        if shortcut.modifiers.contains(.command) { caps.append(("⌘", "command", false)) }
        let label = RecorderButton.label(shortcut)
        let key = String(label.drop { "⌃⌥⇧⌘".contains($0) })
        caps.append(key == "Tab" ? ("⇥", "tab", true) : (key, "", true))
        return caps
    }
    private var keyNames: String { keyCaps.map { $0.word.isEmpty ? $0.symbol : $0.word }.joined(separator: " and ") }
    private var keys: some View {
        HStack(spacing: 8) {
            ForEach(Array(keyCaps.enumerated()), id: \.offset) { _, cap in
                let pressed = cap.isKey ? keyDown : panelShown
                VStack(alignment: .leading, spacing: 1) {
                    Text(cap.symbol).font(.system(size: 13, weight: .semibold))
                    if !cap.word.isEmpty { Text(cap.word).font(.system(size: 9.5, weight: .medium)) }
                }
                .foregroundStyle(OnboardingPalette.ink.opacity(0.85))
                .frame(minWidth: cap.isKey ? 62 : 52, minHeight: 40, alignment: .bottomLeading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(pressed ? 0.8 : 0.95))
                    .shadow(color: .black.opacity(pressed ? 0.12 : 0.3), radius: 0, y: pressed ? 0.5 : 2.5)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white, lineWidth: 0.5))
                .offset(y: pressed ? 2 : 0)
                .modifier(TargetIf(enabled: cap.isKey, id: "key.tab"))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: keyDown)
    }
}
