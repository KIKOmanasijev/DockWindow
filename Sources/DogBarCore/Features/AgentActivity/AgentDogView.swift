import SwiftUI

/// The coats sessions wear. Index is stable for a session's life.
enum AgentCoat {
    struct Palette { let fur: Color; let ear: Color; let dot: Color; let patch: Bool; let perky: Bool }
    static func palette(_ index: Int) -> Palette {
        switch index % AgentActivityStore.coatCount {
        case 0: return Palette(fur: Color(hex: 0xF4A95E), ear: Color(hex: 0xB86A2E), dot: Color(hex: 0xFF9F4A), patch: false, perky: false)
        case 1: return Palette(fur: Color(hex: 0xC4ADFF), ear: Color(hex: 0x7C5BD6), dot: Color(hex: 0xA98BFF), patch: true, perky: true)
        case 2: return Palette(fur: Color(hex: 0x8FCBFF), ear: Color(hex: 0x3F82C7), dot: Color(hex: 0x6DB8FF), patch: false, perky: false)
        case 3: return Palette(fur: Color(hex: 0x8FE0B9), ear: Color(hex: 0x3A9A6E), dot: Color(hex: 0x5ED39A), patch: true, perky: false)
        case 4: return Palette(fur: Color(hex: 0xFFB1C6), ear: Color(hex: 0xC85A7E), dot: Color(hex: 0xFF8DB0), patch: false, perky: true)
        case 5: return Palette(fur: Color(hex: 0xF6DC7A), ear: Color(hex: 0xB8932C), dot: Color(hex: 0xF2CC45), patch: true, perky: false)
        case 6: return Palette(fur: Color(hex: 0xFF9C80), ear: Color(hex: 0xC4522F), dot: Color(hex: 0xFF7A57), patch: false, perky: true)
        default: return Palette(fur: Color(hex: 0xD3AE8F), ear: Color(hex: 0x86593A), dot: Color(hex: 0xC99A74), patch: true, perky: false)
        }
    }
    /// The neutral pup on an empty island.
    static let resting = Palette(fur: Color(hex: 0xB9B3AC), ear: Color(hex: 0x6E6862), dot: Color(hex: 0x8A847E), patch: false, perky: false)
    static let ink = Color(hex: 0x2B1F18)
    static let muzzle = Color(hex: 0xFFF4E6)
}

/// How the dog looks. Derived from status only; never from inferred thinking.
enum AgentMood: Equatable {
    case idle, working, needsYou, finished, troubled, stale
    init(_ session: AgentSession?) {
        guard let session else { self = .idle; return }
        switch session.status {
        case .working: self = .working
        case .needsYou: self = .needsYou
        case .finished: self = session.turnError == nil ? .finished : .troubled
        case .idle: self = .idle
        case .stale: self = .stale
        }
    }
}

/// One finite reaction. A new token restarts from the current pose, so reversals never snap.
struct AgentDogReaction: Equatable {
    enum Kind: Equatable { case none, expand, attention, finish }
    var kind: Kind = .none
    var serial = 0
}

/// Layered transforms the reaction animates. Area is roughly preserved: x and y move oppositely.
struct AgentDogMotion {
    var squashX: Double = 1
    var squashY: Double = 1
    var lift: Double = 0
    var tilt: Double = 0
    var ear: Double = 0
}

/// A simple doodle dog head drawn from vector shapes in a 100×100 design space: floppy or perky
/// ears on hinges, dot eyes, a cream muzzle and a nose. Emotion comes from eyes, brows, mouth and
/// ear set. No bitmap, no idle loop; the only motion is one short reaction per meaningful change.
struct AgentDogView: View {
    let coat: AgentCoat.Palette
    let mood: AgentMood
    let size: CGFloat
    var reaction = AgentDogReaction()
    var reduceMotion = false

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if reduceMotion {
            face(AgentDogMotion())
        } else {
            animated
        }
    }

    private var animated: some View {
        Color.clear.keyframeAnimator(initialValue: AgentDogMotion(), trigger: reaction) { _, motion in
            face(motion)
        } keyframes: { _ in
            Self.keyframes(reaction.kind)
        }
    }

    /// Peak values for one reaction. Every reaction has the same two-beat shape: a quick
    /// ease-out to the peak, then a spring home, so a newer reaction can always take over.
    struct Peaks {
        var squashX = 1.0, squashY = 1.0, lift = 0.0, tilt = 0.0, ear = 0.0
        var attack = 0.06, settle = 0.30, bounce = 0.18
        static func of(_ kind: AgentDogReaction.Kind) -> Peaks {
            // Starting hypotheses from the motion research: 2–4% squash, ≤2° head, ≤5° ears lagging ~35 ms.
            switch kind {
            case .expand: return Peaks(squashX: 1.035, squashY: 0.965, tilt: -1.5, ear: 5)
            case .attention: return Peaks(squashX: 0.975, squashY: 1.03, lift: 2, ear: -5, attack: 0.08, settle: 0.32, bounce: 0.12)
            case .finish: return Peaks(squashX: 1.025, squashY: 0.975, tilt: 2, ear: 3.5, attack: 0.08, settle: 0.32, bounce: 0.12)
            case .none: return Peaks(attack: 0.01, settle: 0.2, bounce: 0)
            }
        }
    }

    static func timeline(_ kind: AgentDogReaction.Kind) -> KeyframeTimeline<AgentDogMotion> {
        KeyframeTimeline(initialValue: AgentDogMotion()) { keyframes(kind) }
    }

    @KeyframesBuilder<AgentDogMotion>
    static func keyframes(_ kind: AgentDogReaction.Kind) -> some Keyframes<AgentDogMotion> {
        let p = Peaks.of(kind)
        let body = Spring(duration: p.settle, bounce: p.bounce)
        let ears = Spring(duration: p.settle + 0.08, bounce: p.bounce == 0 ? 0 : 0.20)
        KeyframeTrack(\.squashX) {
            CubicKeyframe(p.squashX, duration: p.attack)
            SpringKeyframe(1, duration: p.settle, spring: body)
        }
        KeyframeTrack(\.squashY) {
            CubicKeyframe(p.squashY, duration: p.attack)
            SpringKeyframe(1, duration: p.settle, spring: body)
        }
        KeyframeTrack(\.lift) {
            CubicKeyframe(p.lift, duration: p.attack)
            SpringKeyframe(0, duration: p.settle, spring: body)
        }
        KeyframeTrack(\.tilt) {
            CubicKeyframe(p.tilt, duration: p.attack)
            SpringKeyframe(0, duration: p.settle, spring: body)
        }
        KeyframeTrack(\.ear) {
            // Ears follow the head about 35 ms late and settle a little after it.
            LinearKeyframe(0, duration: 0.035)
            CubicKeyframe(p.ear, duration: p.attack)
            SpringKeyframe(0, duration: p.settle + 0.08, spring: ears)
        }
    }

    private func face(_ motion: AgentDogMotion) -> some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 100
            context.scaleBy(x: scale, y: scale)
            // Squash about the chin so the dog stays seated on its baseline.
            context.translateBy(x: 50, y: 88 - motion.lift)
            context.rotate(by: .degrees(motion.tilt))
            context.scaleBy(x: motion.squashX, y: motion.squashY)
            context.translateBy(x: -50, y: -88)
            draw(in: &context, earAngle: motion.ear)
        }
    }

    private var earSet: Double {
        // Positive droops outward, negative perks up. Status, not decoration.
        switch mood {
        case .idle, .stale: return 10
        case .working: return 0
        case .needsYou: return -12
        case .finished: return 4
        case .troubled: return 14
        }
    }

    private func draw(in context: inout GraphicsContext, earAngle: Double) {
        let ink = AgentCoat.ink
        let line = StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round)
        let furColor = mood == .stale ? coat.fur.opacity(0.55) : coat.fur

        // Ears behind the head for perky dogs, in front for floppy ones.
        if coat.perky { drawEars(&context, angle: earAngle, line: line) }

        let head = Path(roundedRect: CGRect(x: 17, y: 26, width: 66, height: 60), cornerRadius: 27, style: .continuous)
        context.fill(head, with: .color(furColor))
        context.stroke(head, with: .color(ink), style: line)

        if coat.patch {
            var patch = Path()
            patch.addEllipse(in: CGRect(x: 54, y: 38, width: 19, height: 17))
            context.fill(patch, with: .color(coat.ear.opacity(0.55)))
        }
        if !coat.perky { drawEars(&context, angle: earAngle, line: line) }

        // Muzzle.
        let muzzle = Path(ellipseIn: CGRect(x: 33, y: 58, width: 34, height: 24))
        context.fill(muzzle, with: .color(AgentCoat.muzzle))
        context.stroke(muzzle, with: .color(ink.opacity(0.85)), style: StrokeStyle(lineWidth: 2.4))

        drawEyes(&context, line: line)
        drawMouth(&context, line: line)

        // Nose: a soft rounded triangle.
        var nose = Path()
        nose.move(to: CGPoint(x: 44.5, y: 62))
        nose.addQuadCurve(to: CGPoint(x: 55.5, y: 62), control: CGPoint(x: 50, y: 59.5))
        nose.addQuadCurve(to: CGPoint(x: 50, y: 68), control: CGPoint(x: 55, y: 66))
        nose.addQuadCurve(to: CGPoint(x: 44.5, y: 62), control: CGPoint(x: 45, y: 66))
        context.fill(nose, with: .color(ink))

        if mood == .finished {
            for x in [27.0, 73.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: 61, width: 10, height: 6)), with: .color(Color(hex: 0xFF7F8E).opacity(0.55)))
            }
        }
    }

    private func drawEars(_ context: inout GraphicsContext, angle: Double, line: StrokeStyle) {
        for side in [-1.0, 1.0] {
            var ear = context
            let hinge = CGPoint(x: 50 + side * 27, y: 33)
            ear.translateBy(x: hinge.x, y: hinge.y)
            ear.rotate(by: .degrees(side * (earSet + angle)))
            var path = Path()
            if coat.perky {
                // A rounded upright ear.
                path.move(to: CGPoint(x: -side * 9, y: 4))
                path.addQuadCurve(to: CGPoint(x: side * 4, y: -22), control: CGPoint(x: -side * 6, y: -18))
                path.addQuadCurve(to: CGPoint(x: side * 11, y: 4), control: CGPoint(x: side * 14, y: -12))
                path.closeSubpath()
            } else {
                // A floppy teardrop hanging beside the cheek.
                path.move(to: CGPoint(x: -side * 7, y: -4))
                path.addQuadCurve(to: CGPoint(x: side * 11, y: 30), control: CGPoint(x: side * 18, y: -2))
                path.addQuadCurve(to: CGPoint(x: -side * 3, y: 26), control: CGPoint(x: side * 6, y: 38))
                path.addQuadCurve(to: CGPoint(x: -side * 7, y: -4), control: CGPoint(x: -side * 10, y: 12))
                path.closeSubpath()
            }
            ear.fill(path, with: .color(mood == .stale ? coat.ear.opacity(0.55) : coat.ear))
            ear.stroke(path, with: .color(AgentCoat.ink), style: line)
        }
    }

    private func drawEyes(_ context: inout GraphicsContext, line: StrokeStyle) {
        let ink = AgentCoat.ink
        for x in [38.0, 62.0] {
            switch mood {
            case .idle:
                // Relaxed, closed: a soft downward curve.
                var path = Path()
                path.move(to: CGPoint(x: x - 5, y: 50))
                path.addQuadCurve(to: CGPoint(x: x + 5, y: 50), control: CGPoint(x: x, y: 54))
                context.stroke(path, with: .color(ink), style: line)
            case .finished:
                // Pleased: upturned arcs.
                var path = Path()
                path.move(to: CGPoint(x: x - 5, y: 52))
                path.addQuadCurve(to: CGPoint(x: x + 5, y: 52), control: CGPoint(x: x, y: 45))
                context.stroke(path, with: .color(ink), style: line)
            case .stale:
                var path = Path()
                path.move(to: CGPoint(x: x - 4.5, y: 50)); path.addLine(to: CGPoint(x: x + 4.5, y: 50))
                context.stroke(path, with: .color(ink.opacity(0.8)), style: line)
            case .working, .needsYou, .troubled:
                let radius = mood == .needsYou ? 5.2 : 4.3
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: 49 - radius, width: radius * 2, height: radius * 2)), with: .color(ink))
                context.fill(Path(ellipseIn: CGRect(x: x - radius * 0.15, y: 49 - radius * 0.75, width: radius * 0.7, height: radius * 0.7)), with: .color(.white))
                if mood != .working {
                    // Brows: raised for attention, worried for an error.
                    var brow = Path()
                    let inner = mood == .needsYou ? 39.0 : 41.5
                    let outer = mood == .needsYou ? 39.0 : 38.0
                    let toward = x < 50 ? 1.0 : -1.0
                    brow.move(to: CGPoint(x: x - toward * 5, y: outer))
                    brow.addLine(to: CGPoint(x: x + toward * 4, y: inner))
                    context.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
            }
        }
    }

    private func drawMouth(_ context: inout GraphicsContext, line: StrokeStyle) {
        let ink = AgentCoat.ink
        let thin = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        switch mood {
        case .finished:
            // Open smile with a little tongue.
            var mouth = Path()
            mouth.move(to: CGPoint(x: 42, y: 71))
            mouth.addQuadCurve(to: CGPoint(x: 58, y: 71), control: CGPoint(x: 50, y: 82))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(ink))
            context.fill(Path(ellipseIn: CGRect(x: 46, y: 73.5, width: 8, height: 5.5)), with: .color(Color(hex: 0xFF7F8E)))
        case .needsYou:
            context.stroke(Path(ellipseIn: CGRect(x: 47, y: 71, width: 6, height: 6.5)), with: .color(ink), style: thin)
        case .troubled:
            var mouth = Path()
            mouth.move(to: CGPoint(x: 44, y: 76))
            mouth.addQuadCurve(to: CGPoint(x: 56, y: 76), control: CGPoint(x: 50, y: 71))
            context.stroke(mouth, with: .color(ink), style: thin)
        case .working:
            // Concentrating: a small straight mouth with the tongue tip out.
            var mouth = Path()
            mouth.move(to: CGPoint(x: 45, y: 73)); mouth.addLine(to: CGPoint(x: 55, y: 73))
            context.stroke(mouth, with: .color(ink), style: thin)
            context.fill(Path(roundedRect: CGRect(x: 52, y: 72.5, width: 5, height: 5), cornerRadius: 2.5), with: .color(Color(hex: 0xFF7F8E)))
        case .idle, .stale:
            // The classic doodle "w".
            var mouth = Path()
            mouth.move(to: CGPoint(x: 43.5, y: 71))
            mouth.addQuadCurve(to: CGPoint(x: 50, y: 71), control: CGPoint(x: 46.75, y: 75.5))
            mouth.addQuadCurve(to: CGPoint(x: 56.5, y: 71), control: CGPoint(x: 53.25, y: 75.5))
            context.stroke(mouth, with: .color(ink), style: thin)
        }
        _ = line
    }
}
