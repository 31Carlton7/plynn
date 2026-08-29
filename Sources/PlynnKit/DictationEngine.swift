import Foundation

/// A streaming dictation engine: feed 16 kHz mono samples, get live partials
/// via callback and a final transcript from finish(). On this Sequoia Intel
/// build the only implementation is `AppleSpeechEngine` (on-device Speech).
public protocol DictationEngine: Actor {
    nonisolated var displayName: String { get }
    /// Load whatever the engine needs (idempotent) and reset for a new session.
    func start() async throws
    func setPartialCallback(_ callback: @escaping @Sendable (String) -> Void) async
    func append(samples: [Float]) async throws
    /// Final transcript — empty string when nothing usable was said.
    func finish() async throws -> String
}
