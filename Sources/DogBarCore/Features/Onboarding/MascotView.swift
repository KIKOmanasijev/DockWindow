import SwiftUI

/// The DogBar dog. Four static poses, swapped by onboarding state with a short settle, plus two
/// one-shot reactions. It is not a rigged character: nothing loops, and nothing moves with
/// Reduce Motion, which keeps only the cross-fade between poses.
struct MascotView: View {
    enum Reaction: Equatable {
        /// A small greeting tilt, anchored at the paws, when the wizard first opens.
        case greet
        /// A short hop when something the user did succeeded, such as a permission turning on.
        case hop
    }
    let pose: MascotPose
    var size: CGFloat
    /// Changing this value plays `reaction` once.
    var reactionToken: Int = 0
    var reaction: Reaction = .hop
    let reduceMotion: Bool
    @State private var tilt: Double = 0
    @State private var lift: CGFloat = 0

    var body: some View {
        ZStack {
            Image(nsImage: OnboardingAssets.mascot(pose))
                .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .id(pose)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.97, anchor: .bottom)),
                    removal: .opacity))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(tilt), anchor: .bottom)
        .offset(y: lift)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.8), value: pose)
        .accessibilityHidden(true)
        .task(id: reactionToken) {
            guard reactionToken > 0, !reduceMotion else { return }
            await play(reaction)
        }
    }

    private func play(_ reaction: Reaction) async {
        switch reaction {
        case .greet:
            for (angle, pause) in [(-3.0, 180), (2.0, 200), (0.0, 260)] {
                withAnimation(.easeInOut(duration: Double(pause) / 1000)) { tilt = angle }
                try? await Task.sleep(for: .milliseconds(pause))
                if Task.isCancelled { tilt = 0; return }
            }
        case .hop:
            withAnimation(.easeOut(duration: 0.16)) { lift = -12 }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { lift = 0 }
        }
    }
}
