import Foundation

public struct FormatResult: Equatable, Sendable {
    public let text: String
    public let pressEnter: Bool
    public let verbatim: String
}

/// The full formatting pipeline: instant rules pass, then optional LLM polish.
/// Every path returns something pasteable; LLM problems degrade to rules output.
public actor TranscriptFormatter {
    private let llm = LLMFormatter()

    public init() {}

    public var llmReady: Bool {
        get async { await llm.ready }
    }

    /// Kick the (large) LLM download/load in the background.
    public func warmLLM() async {
        try? await llm.ensureLoaded()
    }

    public func format(
        _ transcript: String, bundleID: String?, aiPolish: Bool
    ) async -> FormatResult {
        let rules = RulesFormatter.format(transcript)
        var text = rules.text
        if aiPolish, await llm.ready, !text.isEmpty {
            let profile = AppCategories.profile(forBundleID: bundleID)
            text = await llm.format(text, tone: profile.tone, technical: profile.isTechnical)
        }
        return FormatResult(text: text, pressEnter: rules.pressEnter, verbatim: transcript)
    }
}
