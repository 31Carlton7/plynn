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
    private let appleFM = AppleFMFormatter()
    private let llm = LLMFormatter()  // fallback when Apple Intelligence is off
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

    /// Which polish engine is live, for status display. Nil = rules only.
    public var polishEngine: String? {
        get async {
            if appleFM.ready { return "Apple Intelligence" }
            if await llm.ready { return "Qwen3-4B (local)" }
            return nil
        }
    }

    /// Why Apple's model isn't in use (nil when it is).
    public var appleFMStatus: String? {
        appleFM.ready ? nil : appleFM.availabilityDescription
    }

    /// Command mode: apply a spoken instruction to selected text.
    /// Nil = no engine or the transform failed — caller must touch nothing.
    public func transform(selection: String, instruction: String) async -> String? {
        let prompt = TransformPrompt.build(selectedText: selection, instruction: instruction)
        let raw: String?
        if appleFM.ready {
            raw = await appleFM.complete(prompt)
        } else if await llm.ready {
            raw = await llm.complete(prompt)
        } else {
            return nil
        }
        let out = PolishPrompt.sanitize(raw, input: selection)
        return out == selection ? nil : out
    }

    /// Warm the polish path: Apple's on-device model when available,
    /// otherwise the bundled-model fallback (downloads on first use).
    public func warmLLM() async {
        if appleFM.ready {
            await appleFM.warm()
        } else {
            try? await llm.ensureLoaded()
        }
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
        if aiPolish, !text.isEmpty, PolishGate.needsPolish(text) {
            let profile = AppCategories.profile(forBundleID: bundleID)
            let spellings = DictionaryCorrector.relevantTerms(for: text, terms: terms)
            if appleFM.ready {
                text = await appleFM.format(
                    text, tone: profile.tone, technical: profile.isTechnical,
                    preferredSpellings: spellings)
            } else if await llm.ready {
                text = await llm.format(
                    text, tone: profile.tone, technical: profile.isTechnical,
                    preferredSpellings: spellings)
            }
            // The LLM can regress a spelling it saw in the raw text; re-assert.
            text = DictionaryCorrector.correct(text, terms: terms)
        }
        return FormatResult(text: text, pressEnter: rules.pressEnter, verbatim: transcript)
    }
}
