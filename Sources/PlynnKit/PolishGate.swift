import Foundation

/// Decides whether a transcript is worth the LLM's latency. Clean short text
/// pastes instantly on the rules output alone; the LLM only runs when there's
/// something for it to actually fix.
public enum PolishGate {
    /// Whole-word cues that the transcript contains fillers or self-corrections.
    private static let cues = try! NSRegularExpression(
        pattern: #"""
        (?xi)\b(
        um|uh|uhm|erm|
        you\ know|i\ mean|kind\ of\ like|
        actually|no\ wait|scratch\ that|rather|
        basically|literally
        )\b
        """#)

    private static let longDictationWords = 20

    public static func needsPolish(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.count >= longDictationWords { return true }
        let range = NSRange(text.startIndex..., in: text)
        if cues.firstMatch(in: text, range: range) != nil { return true }
        // Spoken enumeration: at least two ordinal cues.
        let lower = text.lowercased()
        let ordinals = ["first", "second", "third", "next point"].filter { lower.contains($0) }
        return ordinals.count >= 2
    }
}
