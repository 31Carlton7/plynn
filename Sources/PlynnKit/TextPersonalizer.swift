import Foundation

/// Replaces spoken snippet triggers ("my email") with their expansions.
/// Whole-phrase, case-insensitive, word-boundary safe.
public enum SnippetExpander {
    public static func expand(_ text: String, snippets: [PersonalStore.Snippet]) -> String {
        var result = text
        for snippet in snippets where !snippet.trigger.isEmpty {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: snippet.trigger) + "\\b"
            result = result.replacingOccurrences(
                of: pattern,
                with: NSRegularExpression.escapedTemplate(for: snippet.expansion),
                options: [.regularExpression, .caseInsensitive])
        }
        return result
    }
}

/// Rewrites ASR near-misses of dictionary terms ("plin" → "Plynn") and
/// enforces canonical casing. Whole-word, case-insensitive.
public enum DictionaryCorrector {
    /// Real English words are never valid ASR-miss aliases: an alias like
    /// "plan" (seen in Wispr imports) would rewrite every genuine use of the
    /// word. Case-only variants of the canonical text are exempt.
    private static let systemWords: Set<String> = {
        guard let content = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)
        else { return [] }
        return Set(content.components(separatedBy: .newlines).map { $0.lowercased() })
    }()

    public static func correct(
        _ text: String, terms: [PersonalStore.Term], commonWords: Set<String>? = nil
    ) -> String {
        let dictionary = commonWords ?? systemWords
        var result = text
        for term in terms where !term.text.isEmpty {
            // Aliases plus the canonical spelling itself (fixes casing).
            for variant in term.aliases + [term.text] where !variant.isEmpty {
                let isCaseVariantOfTerm =
                    variant.caseInsensitiveCompare(term.text) == .orderedSame
                if !isCaseVariantOfTerm, dictionary.contains(variant.lowercased()) { continue }
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: variant) + "\\b"
                result = result.replacingOccurrences(
                    of: pattern,
                    with: NSRegularExpression.escapedTemplate(for: term.text),
                    options: [.regularExpression, .caseInsensitive])
            }
        }
        return result
    }

    /// The ASR near-miss band, scaled to term length. Two edits on a short term
    /// matches most short English words — "SWE" is two edits from "the", "npm"
    /// from "app", "Neo" from "get" — so a flat distance of 2 marked nearly the
    /// whole dictionary relevant to every transcript. Short terms must match at
    /// distance 1; only terms long enough for two edits to stay distinctive get 2.
    static func matchDistance(_ variant: String) -> Int {
        variant.count <= 5 ? 1 : 2
    }

    /// The subset of terms worth telling the LLM about for THIS transcript —
    /// with a large imported dictionary, sending all of it would bloat every
    /// prompt and invites the model to echo the list back as output.
    /// A term is relevant when some transcript word is within the near-miss
    /// band of the term or one of its aliases.
    public static func relevantTerms(
        for text: String, terms: [PersonalStore.Term], limit: Int = 12
    ) -> [String] {
        let words = text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 3 }
        guard !words.isEmpty else { return [] }
        return terms.filter { term in
            let variants = ([term.text] + term.aliases)
                .map { $0.lowercased() }.filter { $0.count >= 3 }
            return variants.contains { variant in
                let allowed = matchDistance(variant)
                return words.contains { word in
                    abs(word.count - variant.count) <= allowed
                        && CorrectionLearner.editDistance(word, variant) <= allowed
                }
            }
        }.prefix(limit).map(\.text)
    }
}
