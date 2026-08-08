import AVFoundation

/// Taps the default input device, converts to 16 kHz mono Float32.
/// start() spins up the engine; stop() tears it down and returns all samples.
public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()

    public init() {}

    public func start() throws {
        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { [weak self] buffer, _ in
            guard let self, let chunk = try? Resampler.convert(buffer: buffer, to: AudioFile.targetFormat)
            else { return }
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
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
