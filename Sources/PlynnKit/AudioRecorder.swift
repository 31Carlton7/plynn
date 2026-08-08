import AVFoundation

public enum AudioLevel {
    /// Root-mean-square level of a sample chunk (0 for empty input).
    public static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}

/// Taps the default input device, converts to 16 kHz mono Float32.
/// start() spins up the engine; stop() tears it down and returns all samples.
public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()

    /// Called on the audio tap thread with each converted 16 kHz chunk —
    /// feeds both the streaming transcriber and the UI level meter.
    public var onChunk: (([Float]) -> Void)?

    public init() {}

    public func start() throws {
        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); defer { lock.unlock() }
        return samples
    }
}
