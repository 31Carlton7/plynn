import Foundation

/// Instant, deterministic formatting: spoken punctuation commands, line
/// breaks, trailing "press enter", spacing and capitalization repair.
/// Runs before (and independently of) the LLM polish pass.
public enum RulesFormatter {
    public struct Result: Equatable, Sendable {
        public let text: String
        public let pressEnter: Bool
    }

    /// Multi-word commands checked first (longest match wins).
    private static let multiWord: [([String], String)] = [
        (["new", "paragraph"], "\n\n"),
        (["new", "line"], "\n"),
        (["next", "line"], "\n"),
        (["question", "mark"], "?"),
        (["exclamation", "point"], "!"),
        (["exclamation", "mark"], "!"),
        (["em", "dash"], "—"),
    ]

    private static let singleWord: [String: String] = [
        "period": ".", "comma": ",", "colon": ":", "semicolon": ";",
    ]

    public static func format(_ raw: String) -> Result {
        var tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)

        // Trailing "press enter" / "hit enter" → strip + flag.
        var pressEnter = false
        if tokens.count >= 2 {
            let last = core(tokens[tokens.count - 1])
            let prev = core(tokens[tokens.count - 2])
            if last == "enter" && (prev == "press" || prev == "hit") {
                pressEnter = true
                tokens.removeLast(2)
            }
        }

        // Substitute commands.
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            if let (words, symbol) = multiWord.first(where: { words, _ in
                words.indices.allSatisfy { j in
                    i + j < tokens.count && core(tokens[i + j]) == words[j]
                }
            }) {
                out.append(symbol)
                i += words.count
            } else if let symbol = singleWord[core(tokens[i])] {
                out.append(symbol)
                i += 1
            } else {
                out.append(tokens[i])
                i += 1
            }
        }

        return Result(text: polish(out), pressEnter: pressEnter)
    }

    /// Command word with any model-attached punctuation stripped ("period." → "period").
    private static func core(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
    }

    private static func polish(_ tokens: [String]) -> String {
        // Join: no leading space before punctuation, no spaces around newlines.
        var s = ""
        for token in tokens {
            if token == "\n" || token == "\n\n" {
                while s.hasSuffix(" ") { s.removeLast() }
                s += token
            } else if [".", ",", "!", "?", ";", ":"].contains(token) {
                while s.hasSuffix(" ") { s.removeLast() }
                s += token
            } else {
                if !s.isEmpty && !s.hasSuffix("\n") { s += " " }
                s += token
            }
        }

        // Dedupe doubled sentence punctuation (from "period." → "." + ".").
        s = s.replacingOccurrences(of: #"([.,!?;:])[.,!?;:]+"#, with: "$1", options: .regularExpression)
        // Collapse runs of spaces (keep newlines).
        s = s.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize: start of text, after sentence enders, after newlines.
        var chars = Array(s)
        var capitalizeNext = true
        for idx in chars.indices {
            let c = chars[idx]
            if capitalizeNext, c.isLetter {
                chars[idx] = Character(c.uppercased())
                capitalizeNext = false
            } else if c == "." || c == "!" || c == "?" || c == "\n" {
                capitalizeNext = true
            } else if !c.isWhitespace {
                capitalizeNext = false
            }
        }
        return String(chars)
    }
}
