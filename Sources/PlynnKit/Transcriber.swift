import Foundation

/// Batch helper used by tests. Upstream this was FluidAudio/Parakeet; here it
/// is a one-shot session on Apple's on-device Speech engine.
public actor Transcriber {
    private let engine = AppleSpeechEngine()

    public init() {}

    public func transcribe(samples: [Float]) async throws -> String {
        try await engine.start()
        try await engine.append(samples: samples)
        return try await engine.finish()
    }
}
