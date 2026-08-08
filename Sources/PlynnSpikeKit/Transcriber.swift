import FluidAudio
import Foundation

/// Wraps FluidAudio's Parakeet Unified (EN) ASR — int8 encoder on the ANE.
/// First call downloads models (~0.6 GB) to Application Support — allow time + network.
public actor Transcriber {
    private var manager: UnifiedAsrManager?

    public init() {}

    private func loadedManager() async throws -> UnifiedAsrManager {
        if let manager { return manager }
        let m = UnifiedAsrManager()
        try await m.loadModels()
        manager = m
        return m
    }

    /// Sub-2s clips come back empty from the model (the classic dictation-app
    /// short-utterance bug) — pad with leading/trailing silence to a 2 s floor.
    private static let minSamples = 32_000
    private static let leadInSamples = 1_600  // 0.1 s

    /// 16 kHz mono Float32 samples in, transcript out.
    public func transcribe(samples: [Float]) async throws -> String {
        let m = try await loadedManager()
        var padded = samples
        if padded.count < Self.minSamples {
            padded = [Float](repeating: 0, count: Self.leadInSamples) + padded
            padded += [Float](repeating: 0, count: Self.minSamples - padded.count)
        }
        return try await m.transcribe(padded)
    }
}
