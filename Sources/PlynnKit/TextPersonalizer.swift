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
    public static func correct(_ text: String, terms: [PersonalStore.Term]) -> String {
        var result = text
        for term in terms where !term.text.isEmpty {
            // Aliases plus the canonical spelling itself (fixes casing).
            for variant in term.aliases + [term.text] where !variant.isEmpty {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: variant) + "\\b"
                result = result.replacingOccurrences(
                    of: pattern,
                    with: NSRegularExpression.escapedTemplate(for: term.text),
                    options: [.regularExpression, .caseInsensitive])
            }
        }
        return result
    }
}
