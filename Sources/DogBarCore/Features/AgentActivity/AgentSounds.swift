import AppKit
import Foundation

/// Soft, short cues for the moments that matter: a session needs you, a turn finished, a turn failed.
/// Synthesized once into small in-memory WAVs (gentle sine tones with a slow, bell-like decay), played
/// quietly through NSSound. Nothing on tool calls, and never more than one cue every couple of seconds.
@MainActor public final class AgentSounds {
    public enum Cue: CaseIterable { case needsYou, finished, failed }
    private var sounds: [Cue: NSSound] = [:]
    private var lastPlayed = Date.distantPast
    static let cooldown: TimeInterval = 2
    static let volume: Float = 0.32

    public init() {}

    public func play(_ cue: Cue, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPlayed) >= Self.cooldown else { return }
        lastPlayed = now
        let sound = sounds[cue] ?? NSSound(data: Self.wav(for: cue))
        sounds[cue] = sound
        sound?.stop()
        sound?.volume = Self.volume
        sound?.play()
    }

    /// Notes (frequency in Hz, start in seconds). Rising for attention, settling down for done, one low note for a failure.
    static func notes(_ cue: Cue) -> [(Double, Double)] {
        switch cue {
        case .needsYou: return [(659.25, 0), (987.77, 0.13)]          // E5 → B5
        case .finished: return [(880.0, 0), (659.25, 0.12), (783.99, 0.24)] // A5 → E5 → G5
        case .failed: return [(392.0, 0), (329.63, 0.16)]             // G4 → E4
        }
    }

    static func wav(for cue: Cue) -> Data {
        let rate = 44_100.0
        let notes = notes(cue)
        let length = (notes.map(\.1).max() ?? 0) + 0.9
        let count = Int(length * rate)
        var samples = [Double](repeating: 0, count: count)
        for (frequency, start) in notes {
            let offset = Int(start * rate)
            for index in 0..<(count - offset) {
                let t = Double(index) / rate
                let attack = min(1, t / 0.012)
                let envelope = attack * exp(-t * 5.5)
                // Mostly fundamental, a touch of octave for a soft bell colour.
                let tone = sin(2 * .pi * frequency * t) + 0.18 * sin(4 * .pi * frequency * t) * exp(-t * 9)
                samples[offset + index] += tone * envelope * 0.32
            }
        }
        let peak = max(1, samples.map(abs).max() ?? 1)
        var pcm = Data(capacity: count * 2)
        for sample in samples {
            var value = Int16(max(-1, min(1, sample / peak * 0.7)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
