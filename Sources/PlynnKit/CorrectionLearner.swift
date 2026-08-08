import Foundation

/// Learns dictionary entries from the user's own edits: diff what Plynn pasted
/// against what the field contains a few seconds later, and keep only the
/// single-word swaps that look like ASR near-misses (small edit distance) —
/// never meaning changes, insertions, or case-only touch-ups.
public enum CorrectionLearner {
    public struct Correction: Equatable, Sendable {
        public let heard: String
        public let corrected: String
    }

    public static func corrections(original: String, edited: String) -> [Correction] {
        let a = words(original)
        let b = words(edited)
        guard !a.isEmpty, !b.isEmpty else { return [] }

        var results: [Correction] = []
        for (deleted, inserted) in substitutionRuns(a, b) {
            // Only clean 1-for-1 word swaps qualify.
            guard deleted.count == 1, inserted.count == 1 else { continue }
            let heard = deleted[0]
            let corrected = inserted[0]
            guard heard.count >= 3, corrected.count >= 3 else { continue }
            let lhs = heard.lowercased()
            let rhs = corrected.lowercased()
            guard lhs != rhs else { continue }  // case-only change
            let distance = editDistance(lhs, rhs)
            guard (1...2).contains(distance) else { continue }  // ASR near-miss band
            results.append(Correction(heard: heard, corrected: corrected))
        }
        return results
    }

    /// Word tokens with edge punctuation stripped.
    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    /// Diff via LCS: aligned regions where a run of tokens in `a` was replaced
    /// by a run of tokens in `b` (case-insensitive matching).
    private static func substitutionRuns(
        _ a: [String], _ b: [String]
    ) -> [(deleted: [String], inserted: [String])] {
        let la = a.map { $0.lowercased() }
        let lb = b.map { $0.lowercased() }
        var table = [[Int]](repeating: [Int](repeating: 0, count: lb.count + 1), count: la.count + 1)
        for i in stride(from: la.count - 1, through: 0, by: -1) {
            for j in stride(from: lb.count - 1, through: 0, by: -1) {
                table[i][j] = la[i] == lb[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var runs: [(deleted: [String], inserted: [String])] = []
        var deleted: [String] = []
        var inserted: [String] = []
        func flush() {
            if !deleted.isEmpty || !inserted.isEmpty {
                runs.append((deleted, inserted))
                deleted = []
                inserted = []
            }
        }
        var i = 0
        var j = 0
        while i < la.count, j < lb.count {
            if la[i] == lb[j] {
                flush()
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                deleted.append(a[i])
                i += 1
            } else {
                inserted.append(b[j])
                j += 1
            }
        }
        deleted.append(contentsOf: a[i...])
        inserted.append(contentsOf: b[j...])
        flush()
        return runs
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let ca = Array(a)
        let cb = Array(b)
        var row = Array(0...cb.count)
        for i in 1...ca.count {
            var previous = row[0]
            row[0] = i
            for j in 1...cb.count {
                let cost = ca[i - 1] == cb[j - 1] ? previous : previous + 1
                previous = row[j]
                row[j] = min(cost, row[j] + 1, row[j - 1] + 1)
            }
        }
        return row[cb.count]
    }
}
