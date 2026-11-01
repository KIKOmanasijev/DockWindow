import AppKit
import SwiftUI

// The DogBar dog as a layered puppet cut from the four mascot poses (Scripts/mascot_rig.py):
// a body, a tail that wags behind it, a raised forearm that waves or scratches, eyelids that
// blink, and paws that can grip an edge in front of whatever the dog peeks over. Scenes direct
// it with short, single-purpose moves. Nothing loops; Reduce Motion keeps only pose changes.

/// One cut-out pose of the rig.
enum MascotFrame: String {
    /// Smiling, one paw raised. The paw waves.
    case wave
    /// Curious closed smile, one paw raised by its ear. The paw scratches.
    case think
    /// Facing right, one paw presenting or touching something.
    case guide
    /// Both paws up.
    case celebrate

    var hasArm: Bool { self == .wave || self == .think }
    var tail: String { self == .wave || self == .think ? "welcome-tail" : "\(rawValue)-tail" }
    /// The original pose, used when rig layers are missing.
    var fallback: MascotPose {
        switch self { case .wave: .welcome; case .think: .permissions; case .guide: .guide; case .celebrate: .celebrate }
    }
    /// Eye boxes on the 1254 px canvas and the fur colour above each.
    var eyes: [(rect: CGRect, lid: UInt32)] {
        switch self {
        case .wave: [(CGRect(x: 550, y: 260, width: 90, height: 85), 0xFCB85E), (CGRect(x: 755, y: 320, width: 90, height: 92), 0xFBB75F)]
        case .think: [(CGRect(x: 550, y: 270, width: 95, height: 90), 0xFCBB69), (CGRect(x: 762, y: 330, width: 95, height: 95), 0xFBB766)]
        case .guide: [(CGRect(x: 555, y: 295, width: 95, height: 92), 0xFCBD68), (CGRect(x: 765, y: 270, width: 80, height: 87), 0xFCBC67)]
        case .celebrate: [(CGRect(x: 550, y: 260, width: 90, height: 90), 0xFCB55E), (CGRect(x: 757, y: 320, width: 90, height: 90), 0xFBB35E)]
        }
    }
}

/// Points on the rig canvas, as fractions of its size.
@MainActor enum MascotRig {
    static let canvas: CGFloat = 1254
    static let tailPivot = UnitPoint(x: 390 / canvas, y: 1000 / canvas)
    static let armPivot = UnitPoint(x: 440 / canvas, y: 760 / canvas)
    /// The guide pose's outstretched paw, for touching a target.
    static let guidePaw = CGPoint(x: 1205 / canvas, y: 600 / canvas)
    /// Where an edge the dog peeks over crosses the rig: at the bottom of the raised paws, so
    /// they rest on top of the edge rather than hanging in front of it.
    static let peekEdge: CGFloat = 648 / canvas
    /// How far the paw tips overlap the edge's rim.
    static let pawOverlap: CGFloat = 14 / canvas
    /// Clear the glossy rim instead of painting paw pixels over its highlight.
    static let rimClearance: CGFloat = 4
    static var layers: [String] {
        ["wave-body", "think-body", "arm", "welcome-tail", "guide-body", "guide-tail", "celebrate-body", "celebrate-tail", "celebrate-paws"]
    }
    static func image(_ name: String) -> NSImage? { OnboardingAssets.image("Rig/\(name).png") }
}

struct MascotState: Equatable {
    var frame: MascotFrame
    /// Degrees. Positive swings the tail up and out.
    var tail: Double = 0
    /// Degrees around the elbow. Positive moves the paw towards the head.
    var arm: Double = 0
    /// Degrees around the feet. Positive leans right (towards a guide target).
    var lean: Double = 0
    /// Points up. Negative sinks the dog, for example behind an edge.
    var lift: CGFloat = 0
    /// Horizontal travel in points.
    var x: CGFloat = 0
    /// Positive squashes, negative stretches. About ±1.
    var squash: CGFloat = 0
    /// 0 open, 1 closed.
    var blink: CGFloat = 0
    var mirrored = false
    var opacity: Double = 1
}

/// Runs the dog's moves. Each move is short and awaits its own end; a cancelled scene task
/// stops it between beats. With Reduce Motion only the end state is applied.
@MainActor final class MascotDirector: ObservableObject {
    @Published var state: MascotState
    var reduceMotion = false
    private(set) var isPerforming = false
    private var reaction: Task<Void, Never>?

    init(_ state: MascotState) { self.state = state }

    func set(_ animation: Animation? = .spring(response: 0.4, dampingFraction: 0.8), _ change: (inout MascotState) -> Void) {
        if reduceMotion || animation == nil { var next = state; change(&next); state = next }
        else { withAnimation(animation) { change(&state) } }
    }
    /// Sleeps for a beat; false once the scene is gone.
    @discardableResult func beat(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        return !Task.isCancelled
    }
    /// Marks a scene choreography, so hover and click reactions wait for it.
    func perform(_ moves: () async -> Void) async {
        isPerforming = true
        await moves()
        isPerforming = false
    }

    func blink() async {
        guard !reduceMotion else { return }
        set(.easeIn(duration: 0.07)) { $0.blink = 1 }
        guard await beat(0.11) else { state.blink = 0; return }
        set(.easeOut(duration: 0.13)) { $0.blink = 0 }
        await beat(0.13)
    }
    func wag(_ times: Int = 3) async {
        guard !reduceMotion else { return }
        for _ in 0..<times {
            set(.easeInOut(duration: 0.14)) { $0.tail = 9 }
            guard await beat(0.14) else { break }
            set(.easeInOut(duration: 0.14)) { $0.tail = -6 }
            guard await beat(0.14) else { break }
        }
        set(.spring(response: 0.35, dampingFraction: 0.7)) { $0.tail = 0 }
    }
    func wave(_ times: Int = 2) async {
        guard !reduceMotion else { return }
        for _ in 0..<times {
            set(.easeInOut(duration: 0.17)) { $0.arm = -11 }
            guard await beat(0.17) else { break }
            set(.easeInOut(duration: 0.17)) { $0.arm = 9 }
            guard await beat(0.17) else { break }
        }
        set(.spring(response: 0.35, dampingFraction: 0.7)) { $0.arm = 0 }
        await beat(0.2)
    }
    /// The paw rubs beside the ear, with a small puzzled lean.
    func scratch(_ times: Int = 4) async {
        guard !reduceMotion else { return }
        set(.easeOut(duration: 0.2)) { $0.arm = 9; $0.lean = -2 }
        guard await beat(0.2) else { return }
        for _ in 0..<times {
            set(.easeInOut(duration: 0.085)) { $0.arm = 15 }
            guard await beat(0.085) else { break }
            set(.easeInOut(duration: 0.085)) { $0.arm = 7 }
            guard await beat(0.085) else { break }
        }
        set(.spring(response: 0.4, dampingFraction: 0.75)) { $0.arm = 0; $0.lean = 0 }
        await beat(0.3)
    }
    func hop(_ height: CGFloat = 16) async {
        guard !reduceMotion else { return }
        set(.easeOut(duration: 0.08)) { $0.squash = 0.8 }
        guard await beat(0.08) else { return }
        set(.easeOut(duration: 0.18)) { $0.lift = height; $0.squash = -0.6 }
        guard await beat(0.18) else { return }
        set(.easeIn(duration: 0.16)) { $0.lift = 0; $0.squash = 0.5 }
        guard await beat(0.16) else { return }
        set(.spring(response: 0.3, dampingFraction: 0.5)) { $0.squash = 0 }
        await beat(0.2)
    }
    /// A quick lean onto a target, as if pressing it.
    func tap(_ degrees: Double = 5) async {
        guard !reduceMotion else { return }
        set(.easeOut(duration: 0.1)) { $0.lean = degrees; $0.squash = 0.25 }
        guard await beat(0.12) else { return }
        set(.spring(response: 0.3, dampingFraction: 0.6)) { $0.lean = 0; $0.squash = 0 }
        await beat(0.18)
    }
    /// Changes pose with a small settle, so the swap reads as a movement.
    func pose(_ frame: MascotFrame) async {
        guard state.frame != frame else { return }
        set(.easeInOut(duration: 0.14)) { $0.frame = frame; $0.squash = reduceMotion ? 0 : 0.35 }
        guard !reduceMotion, await beat(0.12) else { return }
        set(.spring(response: 0.35, dampingFraction: 0.6)) { $0.squash = 0 }
    }
    /// Hover and click reactions, skipped while the scene is performing.
    func react() {
        guard !isPerforming, !reduceMotion else { return }
        isPerforming = true
        reaction = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.blink()
            if self.state.frame.hasArm { await self.wave(1) } else { await self.hop(10) }
            await self.wag(2)
            self.isPerforming = false
        }
    }
    /// Ends a hover or click reaction when the dog leaves the screen. Scene choreography is a
    /// `.task` and is cancelled by SwiftUI.
    func stop() {
        reaction?.cancel(); reaction = nil
        if isPerforming { isPerforming = false }
    }
}

/// Draws the rig. With `peek`, the dog is cut off at an edge across its chin (the top of
/// whatever it peeks over) and its paws are drawn in front of that edge.
struct MascotRigView: View {
    @ObservedObject var dog: MascotDirector
    var size: CGFloat
    var peek = false

    var body: some View {
        let state = dog.state
        ZStack {
            if peek {
                // Behind the edge: only what is above it shows.
                posed(front: false)
                    .mask(alignment: .top) { Rectangle().frame(height: size * MascotRig.peekEdge) }
                // Paw tips curl over the rim, in front of it.
                posed(front: true)
                    .mask(alignment: .top) { Rectangle().frame(height: size * (MascotRig.peekEdge + MascotRig.pawOverlap)) }
                    .modifier(PawsReveal(lift: state.lift, size: size))
            } else {
                // Unclipped, so hops and leans never cut off the head.
                posed(front: false)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(x: state.mirrored ? -1 : 1, y: 1)
        .opacity(state.opacity)
        .offset(x: state.x)
        .contentShape(Rectangle().inset(by: size * 0.15))
        .onTapGesture { dog.react() }
        .onHover { if $0 { dog.react() } }
        .onDisappear { dog.stop() }
        .accessibilityHidden(true)
    }

    private func posed(front: Bool) -> some View {
        let state = dog.state
        return ZStack {
            RigLayers(state: state, size: size, front: front)
                .id(state.frame)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.14), value: state.frame)
        .frame(width: size, height: size)
        .scaleEffect(x: 1 + state.squash * 0.045, y: 1 - state.squash * 0.065, anchor: .bottom)
        .rotationEffect(.degrees(state.lean), anchor: .bottom)
        .offset(y: -state.lift)
    }
}

/// Front paws appear only once the dog has nearly risen to the edge, so no paw shows on the
/// edge while the dog is still hidden behind it. Animatable, so it follows the lift frame by frame.
private struct PawsReveal: ViewModifier, Animatable {
    var lift: CGFloat
    let size: CGFloat
    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(Double(max(0, min(1, 1 + lift / (size * 0.07)))))
    }
}

private struct RigLayers: View {
    let state: MascotState
    let size: CGFloat
    let front: Bool

    var body: some View {
        let frame = state.frame
        if let body = MascotRig.image("\(frame.rawValue)-body") {
            ZStack {
                if front {
                    if frame.hasArm { layer("arm").rotationEffect(.degrees(state.arm), anchor: MascotRig.armPivot) }
                    else if frame == .celebrate { layer("celebrate-paws") }
                } else {
                    layer(frame.tail).rotationEffect(.degrees(state.tail), anchor: MascotRig.tailPivot)
                    image(body)
                    if frame.hasArm { layer("arm").rotationEffect(.degrees(state.arm), anchor: MascotRig.armPivot) }
                    Eyelids(frame: frame, closed: state.blink)
                }
            }
            .frame(width: size, height: size)
        } else if !front {
            // Rig layers missing: the plain pose, still blinking.
            ZStack { image(OnboardingAssets.mascot(frame.fallback)); Eyelids(frame: frame, closed: state.blink) }
                .frame(width: size, height: size)
        }
    }
    @ViewBuilder private func layer(_ name: String) -> some View {
        if let image = MascotRig.image(name) { self.image(image) }
    }
    private func image(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
    }
}

/// Fur-coloured lids that close from the top, leaving a soft closed-eye line.
private struct Eyelids: View, Animatable {
    let frame: MascotFrame
    var closed: CGFloat
    var animatableData: CGFloat {
        get { closed }
        set { closed = newValue }
    }
    var body: some View {
        Canvas { context, size in
            guard closed > 0.01 else { return }
            let scale = size.width / MascotRig.canvas
            for eye in frame.eyes {
                let base = CGRect(x: eye.rect.minX * scale, y: eye.rect.minY * scale,
                                  width: eye.rect.width * scale, height: eye.rect.height * scale)
                let rect = base.insetBy(dx: -base.width * 0.07, dy: -base.height * 0.07)
                var lid = context
                lid.clip(to: Path(CGRect(x: rect.minX - 1, y: rect.minY - 1, width: rect.width + 2, height: rect.height * min(1, closed) + 1)))
                let color = Color(hex: eye.lid)
                lid.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [color, color.opacity(0.96)]),
                                                                      startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                                      endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                let shut = max(0, (closed - 0.6) / 0.4)
                if shut > 0 {
                    var line = Path()
                    let y = rect.minY + rect.height * 0.58
                    line.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: y - rect.height * 0.04))
                    line.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: y - rect.height * 0.04),
                                      control: CGPoint(x: rect.midX, y: y + rect.height * 0.2))
                    context.stroke(line, with: .color(Color(hex: 0x3B1F14).opacity(shut)),
                                   style: StrokeStyle(lineWidth: max(1, rect.width * 0.08), lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Targets

/// Places a scene can ask the dog to touch: Dock icons, keys, desktops.
struct MascotTargets: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func mascotTarget(_ id: String) -> some View {
        anchorPreference(key: MascotTargets.self, value: .bounds) { [id: $0] }
    }
}

extension MascotRigView {
    /// The rig's centre that puts the guide pose's paw on `point`.
    static func center(touching point: CGPoint, size: CGFloat, mirrored: Bool) -> CGPoint {
        let paw = MascotRig.guidePaw
        let pawX = mirrored ? 1 - paw.x : paw.x
        return CGPoint(x: point.x - (pawX - 0.5) * size, y: point.y - (paw.y - 0.5) * size)
    }
}
