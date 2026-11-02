import AppKit
import SwiftUI

// Small, self-contained feature demos for the Features page, built from the onboarding scene
// parts: the same wallpapers, app icons, glass and window thumbnails. They never show live
// windows. Each plays one take when it comes into view, in four beats: an established scene
// (anticipation), one clear action, a long hold on the result, and a gentle return to the
// opening frame (reset). Replay plays it again. Nothing loops. With Reduce Motion, or while the
// feature is off, each shows a still that explains it. Their static state follows the settings
// below them.

/// Scene size, shared so every hero lines up.
enum DemoMetrics {
    static let size = CGSize(width: 264, height: 166)
    static let radius: CGFloat = 9
    /// The Mac-display bezel around a scene.
    static let bezel: CGFloat = 4
}

/// Timing shared by every take, so all three demos move at one calm pace.
enum DemoPace {
    /// The opening frame is shown before anything moves.
    static let anticipation = 1.1
    /// How long a result stays on screen before the scene resets.
    static let hold = 2.4
    /// One smooth, unhurried curve for travel: slow out, slow in, no overshoot.
    static func travel(_ duration: Double) -> Animation { .timingCurve(0.6, 0, 0.3, 1, duration: duration) }
    /// Things that appear (a preview, the switcher panel) settle without bouncing.
    static let appear = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let reset = Animation.easeInOut(duration: 0.9)
}

/// Runs a scene's timeline only while it can be seen: the Features page is selected, the window
/// is visible and the scene is the topmost one in view. Leaving cancels the take mid-way and
/// returns to the resting frame; a finished take is not replayed until the key changes.
private struct DemoDriver: ViewModifier {
    struct Key: Hashable {
        var active: Bool
        var animated: Bool
        var session: Int
        var replay: Int
        var config: Int
        /// The same take, regardless of whether it is on screen.
        var take: [Int] { [session, replay, config] }
    }
    let key: Key
    /// The resting frame: the take's opening frame when animated, an explanatory still otherwise.
    let rest: @MainActor () -> Void
    let play: @MainActor () async -> Void
    @State private var finished: [Int]?

    func body(content: Content) -> some View {
        content.task(id: key) {
            guard key.active, key.animated, finished != key.take else { rest(); return }
            await play()
            if !Task.isCancelled { finished = key.take }
        }
    }
}

extension View {
    fileprivate func demo(_ key: DemoDriver.Key, rest: @escaping @MainActor () -> Void,
                          play: @escaping @MainActor () async -> Void) -> some View {
        modifier(DemoDriver(key: key, rest: rest, play: play))
    }
}

/// Sleeps for a beat; false once the take was cancelled.
@MainActor private func beat(_ seconds: Double) async -> Bool {
    try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    return !Task.isCancelled
}

/// Applies a change without implicit animations, to reset a scene to its first frame.
@MainActor private func instantly(_ change: () -> Void) {
    var transaction = Transaction(); transaction.disablesAnimations = true
    withTransaction(transaction, change)
}

/// A scene in a small Mac-display bezel, like onboarding's desktops, with Replay in its corner.
private struct DemoFrame<Content: View>: View {
    let label: String
    let canReplay: Bool
    let onReplay: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(width: DemoMetrics.size.width, height: DemoMetrics.size.height)
            .clipShape(RoundedRectangle(cornerRadius: DemoMetrics.radius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .padding(DemoMetrics.bezel)
            .background(RoundedRectangle(cornerRadius: DemoMetrics.radius + DemoMetrics.bezel, style: .continuous).fill(Color(hex: 0x0E0C13)))
            .overlay(RoundedRectangle(cornerRadius: DemoMetrics.radius + DemoMetrics.bezel + 1, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .padding(-1))
            .shadow(color: Color(hex: 0x14043C).opacity(0.28), radius: 14, y: 8)
            .overlay(alignment: .bottomTrailing) {
                if canReplay {
                    Button(action: onReplay) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(OnboardingPalette.ink.opacity(0.85))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.white.opacity(0.86)))
                            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(DemoMetrics.bezel + 6)
                    .help("Replay")
                    .accessibilityLabel("Replay demo")
                }
            }
    }
}

/// Pointer, press and ripple at a point in scene coordinates.
private struct DemoPointer: View {
    let tip: CGPoint
    let pressing: Bool
    let rippleShown: Bool
    let rippleDone: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.white, lineWidth: 2)
                .background(Circle().fill(Color.white.opacity(0.25)))
                .frame(width: 22, height: 22)
                .scaleEffect(rippleDone ? 1.7 : 0.4)
                .opacity(rippleShown ? (rippleDone ? 0 : 0.95) : 0)
                .position(tip)
            // The arrow's hotspot is its tip, at (5, 3.5) in its 24 pt frame.
            PointerCursor()
                .scaleEffect(pressing ? 0.64 : 0.76, anchor: UnitPoint(x: 5 / 24, y: 3.5 / 24))
                .position(x: tip.x + 7, y: tip.y + 8.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Dock & Desktops

/// Desktop 1 is shown settled, with its own Dock. After a beat the view leans back, then glides
/// to Desktop 2, whose Dock already holds different apps, and stays there long enough to compare
/// before gliding home. Desktop and dimming choices change what each Dock holds.
struct DockDemoScene: View {
    let enabled: Bool
    let scope: WindowScope
    let otherApps: OtherDesktopApps
    let singleDot: Bool
    let showTrash: Bool
    let active: Bool
    let session: Int
    let reduceMotion: Bool
    @State private var desk = 0
    /// A small lean against the direction of travel, before the glide.
    @State private var lean: CGFloat = 0
    @State private var replay = 0

    private struct Desk { let wallpaper: String; let name: String; let window: WindowThumb.Kind; let items: [MiniDock.Item] }
    private let desks = [
        Desk(wallpaper: "tahoe", name: "Desktop 1 · Work", window: .slack,
             items: [.init(app: "finder", windows: 0), .init(app: "slack", windows: 2), .init(app: "figma", windows: 1), .init(app: "mail", windows: 1)]),
        Desk(wallpaper: "sequoia-blue", name: "Desktop 2 · Personal", window: .music,
             items: [.init(app: "finder", windows: 0), .init(app: "safari", windows: 1), .init(app: "music", windows: 1), .init(app: "photos", windows: 1)]),
    ]
    private let gap: CGFloat = 8
    private var animated: Bool { enabled && !reduceMotion }

    var body: some View {
        let width = DemoMetrics.size.width
        DemoFrame(label: label, canReplay: animated, onReplay: { replay += 1 }) {
            HStack(spacing: gap) { deskView(0); deskView(1) }
                .offset(x: -CGFloat(desk) * (width + gap) + lean)
                .frame(width: width, height: DemoMetrics.size.height, alignment: .leading)
                .background(Color(hex: 0x0E0C13))
                .overlay(alignment: .top) {
                    HStack(spacing: 4) {
                        ForEach(0..<2, id: \.self) { index in
                            Capsule().fill(Color.white.opacity(index == desk ? 0.95 : 0.45))
                                .frame(width: index == desk ? 12 : 5, height: 5)
                        }
                    }
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(.top, 9)
                }
        }
        .demo(DemoDriver.Key(active: active, animated: animated, session: session, replay: replay,
                             config: [scope.rawValue, otherApps.rawValue].hashValue),
              rest: { instantly { desk = 0; lean = 0 } },
              play: play)
    }

    private func play() async {
        instantly { desk = 0; lean = 0 }
        // Anticipation: Desktop 1 and its Dock, settled.
        guard await beat(DemoPace.anticipation + 0.3) else { return }
        withAnimation(.easeOut(duration: 0.28)) { lean = 7 }
        guard await beat(0.28) else { return }
        // Action: one glide to Desktop 2.
        withAnimation(DemoPace.travel(1.05)) { desk = 1; lean = 0 }
        guard await beat(1.05) else { return }
        // Hold: long enough to read the other Dock.
        guard await beat(DemoPace.hold + 0.4) else { return }
        // Reset: back to Desktop 1.
        withAnimation(DemoPace.travel(1.05)) { desk = 0 }
        _ = await beat(1.05)
    }

    /// What one desktop's Dock shows under the current settings.
    private func dock(_ index: Int) -> (items: [MiniDock.Item], dimmed: Set<String>) {
        let own = desks[index].items
        let others = desks[1 - index].items.filter { $0.app != "finder" }
        var items = own, dimmed = Set<String>()
        if scope == .allDesktops {
            items = desks[0].items + desks[1].items.filter { $0.app != "finder" }
        } else if otherApps == .dimmed {
            items = own + others.map { MiniDock.Item(app: $0.app, windows: 0) }
            dimmed = Set(others.map(\.app))
        }
        if singleDot { items = items.map { MiniDock.Item(app: $0.app, windows: min($0.windows, 1)) } }
        return (items, dimmed)
    }

    private func deskView(_ index: Int) -> some View {
        let desk = desks[index], dock = dock(index)
        return Stage(wallpaper: desk.wallpaper, size: DemoMetrics.size, radius: 0) {
            VStack(spacing: 0) {
                HStack { StageTag(text: desk.name, size: 8.5); Spacer() }.padding(7)
                Spacer(minLength: 0)
                FloatingWindow(kind: desk.window, width: 100)
                Spacer(minLength: 0)
                if enabled {
                    MiniDock(items: dock.items, iconSize: dock.items.count > 5 ? 16 : 19,
                             reduceMotion: reduceMotion, dimmed: dock.dimmed, showsTrash: showTrash)
                        .padding(.bottom, 6)
                } else {
                    StageTag(text: "Using Apple's Dock", size: 8.5).padding(.bottom, 10)
                }
            }
        }
    }

    private var label: String {
        guard enabled else { return "DogBar's Dock is off. Apple's Dock is in use." }
        if scope == .allDesktops { return "Both desktops show one Dock with every open app." }
        return otherApps == .dimmed
            ? "Each desktop's Dock lists its own apps first, then apps from the other desktop dimmed."
            : "Desktop 1's Dock shows Slack, Figma and Mail. Desktop 2's Dock shows Safari, Music and Photos."
    }
}

// MARK: - Previews

/// Cause before effect: the pointer rests on the desktop, travels to Safari in the Dock and
/// hovers; the preview opens after the hover delay; the pointer moves to Hotel booking and
/// clicks; the preview closes and only that window comes forward. The result holds, then the
/// scene returns to its opening frame.
struct PreviewsDemoScene: View {
    let enabled: Bool
    let hoverDelay: Double
    let showTitles: Bool
    let showNewWindowTile: Bool
    let showCPU: Bool
    let showMemory: Bool
    let active: Bool
    let session: Int
    let reduceMotion: Bool
    private enum Pointer { case start, safari, booking }
    @State private var pointer = Pointer.start
    @State private var safariHovered = false
    @State private var previewShown = false
    @State private var bookingHovered = false
    @State private var pressing = false
    @State private var rippleShown = false
    @State private var rippleDone = false
    /// 0 with Lisbon day plan in front, 1 with Hotel booking brought forward. A crossfade, so the
    /// change of order reads as one smooth move.
    @State private var bookingFront = 0.0
    @State private var frames: [String: CGRect] = [:]
    @State private var replay = 0
    private let items: [MiniDock.Item] = [.init(app: "finder", windows: 0), .init(app: "safari", windows: 2),
                                          .init(app: "slack", windows: 1), .init(app: "notes", windows: 1)]
    private var animated: Bool { enabled && !reduceMotion }

    var body: some View {
        DemoFrame(label: label, canReplay: animated, onReplay: { replay += 1 }) {
            Stage(wallpaper: "sequoia", size: DemoMetrics.size, radius: 0) { screen }
        }
        .demo(DemoDriver.Key(active: active, animated: animated, session: session, replay: replay, config: 0),
              rest: rest, play: play)
    }

    private var screen: some View {
        ZStack {
            ZStack {
                FloatingWindow(kind: .booking, width: 108).offset(x: 40, y: -26).scaleEffect(0.985)
                FloatingWindow(kind: .trip, width: 104).offset(x: -36, y: -34)
                FloatingWindow(kind: .booking, width: 108).offset(x: 40, y: -26)
                    .scaleEffect(0.985 + 0.015 * bookingFront)
                    .opacity(bookingFront)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 5) {
                Spacer(minLength: 0)
                if previewShown {
                    preview.transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                }
                MiniDock(items: items, iconSize: 22, highlighted: safariHovered ? "safari" : nil, targets: true)
                    .padding(.bottom, 6)
            }
            if !enabled {
                StageTag(text: "Previews are off", size: 9).offset(y: 22)
            }
        }
        .frame(width: DemoMetrics.size.width, height: DemoMetrics.size.height)
        .backgroundPreferenceValue(MascotTargets.self) { targets in
            GeometryReader { proxy in
                ForEach(Array(targets.keys), id: \.self) { id in
                    if let anchor = targets[id] {
                        Color.clear.onChange(of: proxy[anchor], initial: true) { _, rect in frames[id] = rect }
                    }
                }
            }
        }
        .overlay {
            if enabled, let tip = pointerTip {
                DemoPointer(tip: tip, pressing: pressing, rippleShown: rippleShown, rippleDone: rippleDone)
            }
        }
    }

    private var pointerTip: CGPoint? {
        switch pointer {
        case .start: return CGPoint(x: DemoMetrics.size.width * 0.85, y: DemoMetrics.size.height * 0.63)
        case .safari: return frames["dock.safari"].map { CGPoint(x: $0.midX + 3, y: $0.midY + 1) }
        case .booking: return frames["tile.booking"].map { CGPoint(x: $0.midX + 5, y: $0.midY - 3) }
        }
    }

    /// Animated, the opening frame. Otherwise a still that explains the feature: the preview open
    /// with Hotel booking under the pointer.
    private func rest() {
        instantly {
            pressing = false; rippleShown = false; rippleDone = false; bookingFront = 0
            if animated {
                pointer = .start; safariHovered = false; previewShown = false; bookingHovered = false
            } else {
                safariHovered = enabled; previewShown = enabled; bookingHovered = enabled
                pointer = enabled ? .booking : .start
            }
        }
    }

    private func play() async {
        instantly {
            pointer = .start; safariHovered = false; previewShown = false; bookingHovered = false
            pressing = false; rippleShown = false; rippleDone = false; bookingFront = 0
        }
        // Anticipation: two Safari windows, Lisbon day plan in front, the pointer resting.
        guard await beat(DemoPace.anticipation) else { return }
        // 1. The pointer travels to Safari in the Dock and rests there.
        withAnimation(DemoPace.travel(0.95)) { pointer = .safari }
        guard await beat(0.95) else { return }
        withAnimation(.easeOut(duration: 0.15)) { safariHovered = true }
        // 2. After the hover delay (kept short here), the preview opens. Time to read it.
        guard await beat(min(max(hoverDelay, 0.3), 0.8)) else { return }
        withAnimation(DemoPace.appear) { previewShown = true }
        guard await beat(1.1), frames["tile.booking"] != nil else { return }
        // 3. The pointer travels to Hotel booking; only that tile highlights.
        withAnimation(DemoPace.travel(0.8)) { pointer = .booking }
        guard await beat(0.8) else { return }
        withAnimation(.easeOut(duration: 0.15)) { bookingHovered = true }
        guard await beat(0.5) else { return }
        // 4. Click.
        withAnimation(.easeOut(duration: 0.1)) { pressing = true; rippleShown = true }
        withAnimation(.easeOut(duration: 0.55)) { rippleDone = true }
        guard await beat(0.15) else { return }
        withAnimation(.easeOut(duration: 0.12)) { pressing = false }
        guard await beat(0.2) else { return }
        // 5. The preview closes, then only Hotel booking comes forward.
        withAnimation(.easeIn(duration: 0.22)) { previewShown = false; safariHovered = false }
        guard await beat(0.3) else { return }
        withAnimation(.easeInOut(duration: 0.5)) { bookingFront = 1 }
        // Hold on the result.
        guard await beat(0.5 + DemoPace.hold) else { return }
        // Reset: Lisbon day plan returns to the front and the pointer to where it started.
        withAnimation(DemoPace.reset) { bookingFront = 0; bookingHovered = false; pointer = .start; rippleShown = false; rippleDone = false }
        _ = await beat(0.9)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                AppIconImage(name: "safari", size: 10)
                Text("Safari").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.black.opacity(0.85))
                if let usage { Text(usage).font(.system(size: 7.5)).foregroundStyle(.black.opacity(0.5)) }
            }
            HStack(alignment: .top, spacing: 5) {
                tile(.trip, "Lisbon day plan", hovered: false)
                tile(.booking, "Hotel booking", hovered: bookingHovered).mascotTarget("tile.booking")
                if showNewWindowTile {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .overlay(Image(systemName: "plus").font(.system(size: 9, weight: .semibold)).foregroundStyle(.black.opacity(0.5)))
                        .frame(width: 24, height: 42)
                        .padding(.top, 4)
                }
            }
        }
        .padding(7)
        .glass(RoundedRectangle(cornerRadius: 11, style: .continuous), style: .light, shadow: 0.5)
    }
    private var usage: String? {
        let parts = [showCPU ? "4% CPU" : nil, showMemory ? "612 MB" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private func tile(_ kind: WindowThumb.Kind, _ title: String, hovered: Bool) -> some View {
        VStack(spacing: 3) {
            WindowThumb(kind: kind)
            if showTitles {
                Text(title).font(.system(size: 7, weight: .medium)).foregroundStyle(.black.opacity(0.85)).lineLimit(1)
            }
        }
        .padding(4).frame(width: 64)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(hovered ? 0.11 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(hovered ? OnboardingPalette.purple.opacity(0.75) : Color.white.opacity(0.1), lineWidth: hovered ? 1.25 : 1))
        .scaleEffect(hovered && pressing ? 0.96 : 1)
    }

    private var label: String {
        guard enabled else { return "Dock previews are off." }
        return "Hovering Safari in the Dock opens a preview of its two windows. Clicking Hotel booking closes the preview and brings only that window forward."
    }
}

// MARK: - Switcher

/// The keys rest; the modifier goes down; each tap of the key moves the selection, and the panel
/// appears after the switcher's delay; on release Packing list comes to the front. The result
/// holds, then the scene returns to its opening frame. Follows the mode, shortcut and selection
/// color. In macOS mode it shows Apple's switcher as a still.
struct SwitcherDemoScene: View {
    let mode: SwitcherMode
    let shortcut: KeyboardShortcut
    let appearanceDelay: Double
    let selectionColor: Color
    let active: Bool
    let session: Int
    let reduceMotion: Bool
    @State private var panelShown = false
    @State private var selected = 0
    @State private var modifiersDown = false
    @State private var keyDown = false
    /// 0 with Lisbon day plan in front, 1 with Packing list brought forward.
    @State private var notesFront = 0.0
    @State private var replay = 0
    private let windows: [(kind: WindowThumb.Kind, app: String, name: String)] = [
        (.trip, "safari", "Lisbon day plan"), (.booking, "safari", "Hotel booking"), (.notes, "notes", "Packing list"), (.slack, "slack", "#lisbon-trip"),
    ]
    private let apps: [(app: String, name: String)] = [("safari", "Safari"), ("slack", "Slack"), ("notes", "Notes"), ("music", "Music")]
    private var animated: Bool { mode != .native && !reduceMotion }

    var body: some View {
        DemoFrame(label: label, canReplay: animated, onReplay: { replay += 1 }) {
            Stage(wallpaper: "sonoma", size: DemoMetrics.size, radius: 0) {
                ZStack {
                    FloatingWindow(kind: .notes, width: 96).offset(x: -38, y: -36)
                    FloatingWindow(kind: .trip, width: 104).offset(x: 38, y: -24)
                    FloatingWindow(kind: .notes, width: 96).offset(x: -38, y: -36)
                        .scaleEffect(0.985 + 0.015 * notesFront)
                        .opacity(notesFront)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if panelShown {
                        panel.transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
                    }
                    keys
                }
                .padding(.bottom, 10)
            }
        }
        .demo(DemoDriver.Key(active: active, animated: animated, session: session, replay: replay,
                             config: mode.hashValue),
              rest: rest, play: play)
    }

    /// Animated, the opening frame. Otherwise the panel open on Packing list.
    private func rest() {
        instantly {
            keyDown = false; notesFront = 0
            if animated {
                panelShown = false; selected = 0; modifiersDown = false
            } else {
                panelShown = true; selected = mode == .native ? 1 : 2; modifiersDown = true
            }
        }
    }

    private func play() async {
        instantly { panelShown = false; selected = 0; modifiersDown = false; keyDown = false; notesFront = 0 }
        // Anticipation: the desktop and the shortcut's keys, at rest.
        guard await beat(DemoPace.anticipation) else { return }
        withAnimation(.easeOut(duration: 0.12)) { modifiersDown = true }
        guard await beat(0.45) else { return }
        // First tap selects the next window; the panel appears after the switcher's delay.
        guard await tap(select: 1) else { return }
        guard await beat(min(max(appearanceDelay, 0.1), 0.6)) else { return }
        withAnimation(DemoPace.appear) { panelShown = true }
        guard await beat(1.0) else { return }
        guard await tap(select: 2) else { return }
        guard await beat(1.0) else { return }
        // Releasing the modifier goes straight to the selected window.
        withAnimation(.easeOut(duration: 0.12)) { modifiersDown = false }
        withAnimation(.easeIn(duration: 0.22)) { panelShown = false }
        guard await beat(0.3) else { return }
        withAnimation(.easeInOut(duration: 0.5)) { notesFront = 1 }
        // Hold on the result.
        guard await beat(0.5 + DemoPace.hold) else { return }
        // Reset to the opening frame.
        withAnimation(DemoPace.reset) { notesFront = 0; selected = 0 }
        _ = await beat(0.9)
    }
    /// One visible key press: down, the selection moves, up.
    private func tap(select index: Int) async -> Bool {
        withAnimation(.easeOut(duration: 0.08)) { keyDown = true }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { selected = index }
        guard await beat(0.16) else { return false }
        withAnimation(.easeOut(duration: 0.1)) { keyDown = false }
        return true
    }

    @ViewBuilder private var panel: some View {
        switch mode {
        case .windows:
            HStack(spacing: 4) {
                ForEach(windows.indices, id: \.self) { index in
                    let window = windows[index]
                    VStack(spacing: 2) {
                        WindowThumb(kind: window.kind)
                        AppIconImage(name: window.app, size: 13).padding(.top, -9).shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                        Text(window.name).font(.system(size: 6.5, weight: .semibold)).foregroundStyle(Color(hex: 0xF3F0FA)).lineLimit(1)
                    }
                    .padding(4).frame(width: 54)
                    .background(selectionBackground(index == selected))
                }
            }
            .padding(6)
            .glass(RoundedRectangle(cornerRadius: 12, style: .continuous), style: .dark, shadow: 0.5)
        case .apps:
            HStack(spacing: 4) {
                ForEach(apps.indices, id: \.self) { index in
                    VStack(spacing: 3) {
                        AppIconImage(name: apps[index].app, size: 30)
                        Text(apps[index].name).font(.system(size: 7, weight: .semibold)).foregroundStyle(Color(hex: 0xF3F0FA)).lineLimit(1)
                    }
                    .padding(5).frame(width: 48)
                    .background(selectionBackground(index == selected))
                }
            }
            .padding(6)
            .glass(RoundedRectangle(cornerRadius: 12, style: .continuous), style: .dark, shadow: 0.5)
        case .native:
            HStack(spacing: 6) {
                ForEach(apps.indices, id: \.self) { index in
                    AppIconImage(name: apps[index].app, size: 30)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(index == selected ? 0.18 : 0)))
                }
            }
            .padding(8)
            .glass(RoundedRectangle(cornerRadius: 14, style: .continuous), style: .light, shadow: 0.5)
        }
    }
    private func selectionBackground(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(on ? selectionColor.opacity(0.55) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(on ? 0.6 : 0), lineWidth: 1))
    }

    private var keyCaps: [(symbol: String, word: String, isKey: Bool)] {
        let shortcut = mode == .native ? KeyboardShortcut(keyCode: 48, modifiers: .command) : shortcut
        var caps: [(String, String, Bool)] = []
        if shortcut.modifiers.contains(.control) { caps.append(("⌃", "control", false)) }
        if shortcut.modifiers.contains(.option) { caps.append(("⌥", "option", false)) }
        if shortcut.modifiers.contains(.shift) { caps.append(("⇧", "shift", false)) }
        if shortcut.modifiers.contains(.command) { caps.append(("⌘", "command", false)) }
        let key = String(RecorderButton.label(shortcut).drop { "⌃⌥⇧⌘".contains($0) })
        caps.append(key == "Tab" ? ("⇥", "tab", true) : (key, "", true))
        return caps
    }
    private var keys: some View {
        HStack(spacing: 5) {
            ForEach(Array(keyCaps.enumerated()), id: \.offset) { _, cap in
                let pressed = cap.isKey ? keyDown : modifiersDown
                VStack(alignment: .leading, spacing: 0) {
                    Text(cap.symbol).font(.system(size: 10, weight: .semibold))
                    if !cap.word.isEmpty { Text(cap.word).font(.system(size: 6.5, weight: .medium)) }
                }
                .foregroundStyle(OnboardingPalette.ink.opacity(0.85))
                .frame(minWidth: cap.isKey ? 38 : 30, minHeight: 22, alignment: .bottomLeading)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(pressed ? 0.78 : 0.95))
                    .shadow(color: .black.opacity(pressed ? 0.1 : 0.28), radius: 0, y: pressed ? 0.5 : 1.5)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2))
                .offset(y: pressed ? 1.5 : 0)
            }
        }
    }

    private var label: String {
        let keys = keyCaps.map { $0.word.isEmpty ? $0.symbol : $0.word }.joined(separator: " and ")
        switch mode {
        case .windows: return "Holding \(keys) opens DogBar's switcher with one tile per window. Releasing brings the selected window, Packing list, to the front."
        case .apps: return "Holding \(keys) opens DogBar's switcher with one icon per app. Releasing brings Notes to the front."
        case .native: return "Apple's Command-Tab switcher is in use. DogBar leaves it alone."
        }
    }
}
