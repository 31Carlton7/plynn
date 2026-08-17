import AVFoundation

public enum AudioLevel {
    /// Root-mean-square level of a sample chunk (0 for empty input).
    public static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// RMS of each fixed-size window across the chunk.
    ///
    /// One value per audio callback moves the meter at buffer rate (~12 Hz),
    /// which reads as laggy no matter how it's drawn. Slicing the same chunk
    /// into short windows yields several envelope points per callback, so the
    /// visualiser can run at UI rate off audio that already arrived.
    public static func envelope(of samples: [Float], windowSize: Int) -> [Float] {
        guard windowSize > 0, !samples.isEmpty else { return [] }
        var points: [Float] = []
        points.reserveCapacity(samples.count / windowSize + 1)
        var start = 0
        while start < samples.count {
            let end = min(start + windowSize, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            points.append((sum / Float(end - start)).squareRoot())
            start = end
        }
        return points
    }

    /// Perceptual 0…1 from a raw RMS.
    ///
    /// Speech lands roughly between −50 and −10 dBFS, and loudness is
    /// logarithmic — scaling raw amplitude linearly leaves normal talking
    /// hugging the floor and shouting pinned at the ceiling. Mapping the dB
    /// range instead keeps the whole span of a voice visible.
    public static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        let floor: Float = -50
        let ceiling: Float = -10
        return min(1, max(0, (db - floor) / (ceiling - floor)))
    }
}

public enum AudioError: Error {
    /// The input device reported no usable format — typically another app
    /// (FaceTime, Zoom) is mid-reconfiguring the shared device.
    case noInputFormat
}

/// Taps the default input device, converts to 16 kHz mono Float32.
/// start() spins up the engine; stop() tears it down and returns all samples.
///
/// When another app engages voice processing on the shared input (FaceTime,
/// Zoom), CoreAudio reconfigures the device and AVAudioEngine posts a
/// configuration-change notification that silently stops the running graph.
/// We observe it and re-arm the tap so capture survives the reconfiguration.
public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private var configObserver: NSObjectProtocol?

    /// Called on the audio tap thread with each converted 16 kHz chunk —
    /// feeds both the streaming transcriber and the UI level meter.
    public var onChunk: (([Float]) -> Void)?

    public init() {}

    public func start() throws {
        samples.removeAll(keepingCapacity: true)
        try armAndStart()
        // A device reconfiguration (another app grabbing/releasing the mic)
        // stops the engine without an error; rebuild the graph when it does.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            try? self.armAndStart()
        }
    }

    /// Install the tap for the current hardware format and (re)start the engine.
    /// Safe to call again after a configuration change.
    private func armAndStart() throws {
        let input = engine.inputNode
        engine.stop()
        input.removeTap(onBus: 0)

        let inFmt = input.outputFormat(forBus: 0)
        // A contended/reconfiguring device reports 0 Hz or 0 channels; installing
        // a tap with that format throws deep in CoreAudio. Fail cleanly instead.
        guard inFmt.sampleRate > 0, inFmt.channelCount > 0 else {
            throw AudioError.noInputFormat
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { [weak self] buffer, _ in
            guard let self, let chunk = try? Resampler.convert(buffer: buffer, to: AudioFile.targetFormat)
            else { return }
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
            self.onChunk?(chunk)
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() -> [Float] {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); defer { lock.unlock() }
        return samples
    }
}
