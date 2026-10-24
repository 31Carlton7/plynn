import Foundation

/// Stitches `SFSpeechRecognizer` results into one transcript.
///
/// On-device recognition on macOS 15 closes an utterance after roughly two
/// seconds of silence and starts the next one from an empty string — the
/// final result only carries the last utterance. Each closed utterance has to
/// be kept here or everything before the last pause is lost.
struct UtteranceAccumulator: Equatable, Sendable {
    private struct Utterance: Equatable, Sendable {
        var text: String
        var segments: Int
    }

    private var committed: [Utterance] = []
    private var current = Utterance(text: "", segments: 0)

    var text: String {
        (committed.map(\.text) + [current.text])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// - Parameters:
    ///   - closed: the recognizer re-sent this utterance with real segment
    ///     timings, which it only does once it has stopped revising it.
    mutating func update(text raw: String, segmentCount: Int, closed: Bool, isFinal: Bool) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if current.text.isEmpty, let last = committed.last, Self.continues(text, last.text) {
            // Still the utterance we just closed (a repeat, or a late revision).
            current = committed.removeLast()
        } else if Self.isRestart(from: current, toSegments: segmentCount) {
            // A new utterance began without the close being reported.
            commitCurrent()
        }

        current = Utterance(text: text, segments: segmentCount)
        if closed || isFinal { commitCurrent() }
    }

    private mutating func commitCurrent() {
        if !current.text.isEmpty { committed.append(current) }
        current = Utterance(text: "", segments: 0)
    }

    private static func continues(_ text: String, _ previous: String) -> Bool {
        !text.isEmpty && text.count >= previous.count
            && text.lowercased().hasPrefix(previous.lowercased())
    }

    /// Revisions inside one utterance change a word or two; a hypothesis
    /// collapsing to half its length or less is the recognizer starting over.
    private static func isRestart(from current: Utterance, toSegments count: Int) -> Bool {
        current.segments >= 4 && count * 2 <= current.segments
    }
}
