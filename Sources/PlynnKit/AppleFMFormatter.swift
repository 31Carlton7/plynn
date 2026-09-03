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

    /// One stateless prompt → raw completion (nil on timeout/error/unavailable).
    public func complete(_ prompt: String) async -> String? {
        guard ready else { return nil }
        return await withTaskTimeout(seconds: 10) {
            try await LanguageModelSession().respond(to: prompt).content
        }
    }

    public func format(
        _ text: String, tone: Tone, technical: Bool, preferredSpellings: [String] = []
    ) async -> String {
        let prompt = PolishPrompt.build(
            transcript: text, tone: tone, technical: technical,
            preferredSpellings: preferredSpellings)
        return PolishPrompt.sanitize(
            await complete(prompt), input: text, glossary: preferredSpellings)
    }
}
