import AVFoundation
import FluidAudio

/// Streaming ASR over FluidAudio's Parakeet Unified streaming manager, with a
/// VAD silence gate at finish() so silence-only sessions can never hallucinate
/// text. Reusable across sessions: call start() before each dictation.
public actor StreamingTranscriber: DictationEngine {
    public nonisolated let displayName = "Parakeet (local)"
    private let variant: StreamingModelVariant
    private var manager: (any StreamingAsrManager)?
    private var vad: VadManager?
    private var sessionSamples: [Float] = []

    /// parakeetUnified1120ms shares its model repo with the offline batch path —
    /// one download covers both — and beats the 2080ms tier on WER and latency.
    public init(variant: StreamingModelVariant = .parakeetUnified1120ms) {
        self.variant = variant
    }

    /// Load models (idempotent) and reset for a new session.
    public func start() async throws {
        if manager == nil {
            manager = variant.createManager()
            try await manager!.loadModels()
        }
        try await manager!.reset()
        sessionSamples.removeAll(keepingCapacity: true)
    }

    public func setPartialCallback(_ callback: @escaping @Sendable (String) -> Void) async {
        await manager?.setPartialTranscriptCallback(callback)
    }

    /// Feed 16 kHz mono Float32 samples; partial transcripts fire via the callback.
    public func append(samples: [Float]) async throws {
        guard let manager else { return }
        sessionSamples.append(contentsOf: samples)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: AudioFile.targetFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try await manager.appendAudio(buffer)
        try await manager.processBufferedAudio()
    }

    /// Trailing silence fed before finish(): flushes the streaming encoder's
    /// look-ahead window so words spoken right before release aren't dropped —
    /// the same short-utterance fix as the batch path, and also pads very short
    /// sessions up to the 2 s floor the model needs to emit anything at all.
    private static let flushPadSamples = 20_000  // 1.25 s
    private static let minSessionSamples = 32_000  // 2 s

    /// Flush and return the final transcript — empty string if VAD saw no speech.
    public func finish() async throws -> String {
        guard let manager else { return "" }
        let spoken = sessionSamples  // VAD judges only real mic audio, not padding
        var pad = Self.flushPadSamples
        if spoken.count + pad < Self.minSessionSamples { pad = Self.minSessionSamples - spoken.count }
        try await append(samples: [Float](repeating: 0, count: pad))
        sessionSamples = spoken
        let text = try await manager.finish()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        if try await hasSpeech(in: sessionSamples) { return text }
        return ""
    }

    private func hasSpeech(in samples: [Float]) async throws -> Bool {
        guard !samples.isEmpty else { return false }
        if vad == nil { vad = try await VadManager() }
        let results = try await vad!.process(samples)
        return results.contains { $0.isVoiceActive }
    }
}

extension Array {
    /// Split into consecutive slices of at most `size` elements.
    public func chunks(of size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
