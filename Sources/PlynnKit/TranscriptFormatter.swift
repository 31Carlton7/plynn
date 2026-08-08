import Foundation

public struct FormatResult: Equatable, Sendable {
    public let text: String
    public let pressEnter: Bool
    public let verbatim: String
}

/// The full formatting pipeline: rules pass, snippet expansion, dictionary
/// correction, then optional LLM polish. Every path returns something
/// pasteable; LLM problems degrade to the deterministic output.
public actor TranscriptFormatter {
    private let llm = LLMFormatter()
    /// Reloaded per call so Settings edits apply immediately.
    private let personalization: @Sendable () -> (
        snippets: [PersonalStore.Snippet], terms: [PersonalStore.Term]
    )

    public init(
        personalization: @escaping @Sendable () -> (
            snippets: [PersonalStore.Snippet], terms: [PersonalStore.Term]
        ) = { ([], []) }
    ) {
        self.personalization = personalization
    }

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
        let (snippets, terms) = personalization()
        let rules = RulesFormatter.format(transcript)
        var text = rules.text
        text = SnippetExpander.expand(text, snippets: snippets)
        text = DictionaryCorrector.correct(text, terms: terms)
        // Latency gate: clean short dictations paste instantly; the LLM only
        // runs when there are fillers/backtracks/lists to fix or it's long.
        if aiPolish, await llm.ready, !text.isEmpty, PolishGate.needsPolish(text) {
            let profile = AppCategories.profile(forBundleID: bundleID)
            text = await llm.format(
                text, tone: profile.tone, technical: profile.isTechnical,
                preferredSpellings: terms.map(\.text))
            // The LLM can regress a spelling it saw in the raw text; re-assert.
            text = DictionaryCorrector.correct(text, terms: terms)
        }
        return FormatResult(text: text, pressEnter: rules.pressEnter, verbatim: transcript)
    }
}
