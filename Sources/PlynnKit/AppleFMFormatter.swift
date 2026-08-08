import Foundation
import FoundationModels

/// AI polish on Apple's on-device Foundation Model (Apple Intelligence).
/// The default polish engine — no download, Apple-tuned for the hardware.
/// Falls back to the input text on every failure mode, like all polish paths.
public actor AppleFMFormatter {
    public init() {}

    public nonisolated var ready: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Human-readable availability, for logs and Settings.
    public nonisolated var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "available"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled in System Settings"
        case .unavailable(.modelNotReady):
            return "model still downloading — will be used once ready"
        case .unavailable(.deviceNotEligible):
            return "this Mac doesn't support Apple Intelligence"
        case .unavailable(let reason):
            return "unavailable (\(reason))"
        }
    }

    /// Ask the system to page the model in so the first dictation is fast.
    public func warm() {
        guard ready else { return }
        LanguageModelSession().prewarm()
    }

    public func format(
        _ text: String, tone: Tone, technical: Bool, preferredSpellings: [String] = []
    ) async -> String {
        guard ready else { return text }
        let prompt = PolishPrompt.build(
            transcript: text, tone: tone, technical: technical,
            preferredSpellings: preferredSpellings)
        let result: String? = await withTaskTimeout(seconds: 8) {
            let session = LanguageModelSession()  // stateless per dictation
            return try await session.respond(to: prompt).content
        }
        return PolishPrompt.sanitize(result, input: text)
    }
}
