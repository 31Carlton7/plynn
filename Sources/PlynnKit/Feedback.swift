import AVFoundation
import AppKit

/// Sound and haptic cues for the dictation lifecycle.
///
/// Dictation is an eyes-off interaction — you are looking at the app you're
/// typing into, not at the capsule — so each transition gets a cue you can
/// recognise without looking. The two channels are independently switchable;
/// haptics no-op on Macs without a Force Touch trackpad, and AppKit already
/// respects the system "Force Click and haptic feedback" setting for us.
@MainActor
public enum Feedback {
    public enum Cue: String, Sendable {
        /// Mic opened, push-to-talk.
        case start
        /// Double-tap engaged hands-free.
        case lock
        /// Key released; transcript is being polished.
        case stop
        /// Text landed in the target app.
        case success
        /// Recording thrown away (escape, interrupt, secure field).
        case cancel
        /// Mic unavailable, or a command transform that came back empty.
        case failure
    }

    public static var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEffects") as? Bool ?? true
    }

    public static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true
    }

    public static func play(_ cue: Cue) {
        if soundEnabled, let chime = chime(for: cue) {
            ChimePlayer.shared.play(chime, id: cue.rawValue)
        }
        if hapticsEnabled, let pattern = pattern(for: cue) {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
    }

    /// Synthesised rather than sampled — the system alert sounds are instantly
    /// recognisable as "an alert fired in some app", the opposite of what a
    /// dictation cue should feel like.
    ///
    /// Deliberately dull. These fire many times an hour, and at that rate the
    /// things that make a sound *pleasant* once — bright harmonics, a rising
    /// arpeggio, a long ring — are exactly what make it grating by the tenth
    /// time. So: near-sine timbre, a register below where the ear is most
    /// sensitive, and short enough to read as a tick rather than a tune.
    private static func chime(for cue: Cue) -> Chime? {
        switch cue {
        // Single soft G4. Nothing to announce — you know you pressed the key.
        case .start:
            return Chime(notes: [392.00], noteDuration: 0.05,
                         amplitude: 0.06, shimmer: 0.04, decay: 26)
        // G4→D5. The one cue that should stand out: hands-free is a mode you
        // can otherwise forget you're in.
        case .lock:
            return Chime(notes: [392.00, 587.33], noteDuration: 0.07,
                         amplitude: 0.11, shimmer: 0.07, decay: 17)
        // Silent by design: the capsule already flips to "Polishing…", and a
        // cue here would collide with the success cue a moment later.
        case .stop:
            return nil
        // C5→F5, a small step up. Was a bright triad, which is lovely once and
        // tiresome all day.
        case .success:
            return Chime(notes: [523.25, 698.46], noteDuration: 0.055,
                         amplitude: 0.075, shimmer: 0.08, decay: 18)
        // B4→G4, falling: undone.
        case .cancel:
            return Chime(notes: [493.88, 392.00], noteDuration: 0.055,
                         amplitude: 0.07, shimmer: 0.04, decay: 21)
        // G3→E♭3, low and dull. Reads as wrong without being an alarm.
        case .failure:
            return Chime(notes: [196.00, 155.56], noteDuration: 0.08,
                         amplitude: 0.11, shimmer: 0.05, decay: 13)
        }
    }

    private static func pattern(for cue: Cue) -> NSHapticFeedbackManager.FeedbackPattern? {
        switch cue {
        // A single detent as the mic opens and as the text lands.
        case .start, .success: return .generic
        // Heavier: hands-free is a mode change you should feel distinctly.
        case .lock: return .levelChange
        // Faint tick on release, so the handoff to polishing is felt.
        case .stop: return .alignment
        case .cancel, .failure: return .generic
        }
    }
}

/// A tiny additive-synth voice: sine partials under an exponential decay,
/// played as a short sequence of notes whose tails ring into each other.
struct Chime {
    /// Frequencies in Hz, struck in order.
    let notes: [Double]
    /// Seconds between strikes (each note rings well past the next).
    let noteDuration: Double
    /// Peak amplitude before soft clipping, 0…1.
    let amplitude: Double
    /// Level of the octave and twelfth partials — higher reads glassier.
    let shimmer: Double
    /// Exponential decay rate; higher is shorter and drier.
    let decay: Double
}

/// Renders chimes once and plays them through a persistent output engine.
/// Separate from the recorder's engine — macOS is happy to run both, and this
/// one stays up so a cue never pays for engine start-up.
@MainActor
private final class ChimePlayer {
    static let shared = ChimePlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var wired = false

    func play(_ chime: Chime, id: String) {
        guard let buffer = cache[id] ?? render(chime) else { return }
        cache[id] = buffer
        guard prepared() else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
        player.play()
    }

    /// Lazily wires the graph, and re-starts it if the audio device changed
    /// out from under us (unplugging headphones stops the engine).
    private func prepared() -> Bool {
        if !wired {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            wired = true
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch {
                NSLog("plynn: cue engine unavailable \(error)")
                return false
            }
        }
        return true
    }

    private func render(_ chime: Chime) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        // Enough room for the last strike to decay to silence.
        let tail = 0.5
        let seconds = Double(max(chime.notes.count - 1, 0)) * chime.noteDuration + tail
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frames

        let channelCount = Int(format.channelCount)
        for frame in 0..<Int(frames) {
            let t = Double(frame) / rate
            var sample = 0.0
            for (index, frequency) in chime.notes.enumerated() {
                let onset = Double(index) * chime.noteDuration
                guard t >= onset else { continue }
                let local = t - onset
                // 3 ms attack ramp — instant onset would click.
                let envelope = (1 - exp(-local / 0.003)) * exp(-local * chime.decay)
                let phase = 2 * .pi * frequency * local
                // Octave only. The twelfth is what gave these a glassy edge,
                // and that edge is the part that grates on repetition.
                sample += envelope * (sin(phase) + chime.shimmer * sin(phase * 2))
            }
            // tanh rounds the peaks off instead of letting stacked notes clip.
            let value = Float(tanh(sample * chime.amplitude))
            for channel in 0..<channelCount { channels[channel][frame] = value }
        }
        return buffer
    }
}
