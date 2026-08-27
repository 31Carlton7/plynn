import Foundation

/// Adds deterministic file tags for known personal dictionary terms.
///
/// A term such as `main.swift` also matches the spoken form `main dot swift`.
/// The resolver never searches the filesystem and never invents a filename:
/// only an explicitly configured dictionary term can become a tag.
public enum ReferenceResolver {
    private struct Candidate {
        let phrase: String
        let canonical: String
    }

    public static func tagFileReferences(
        _ text: String, terms: [PersonalStore.Term]
    ) -> String {
        guard !text.isEmpty else { return text }

        let candidates = terms.flatMap(candidates(for:))
            .sorted {
                if $0.phrase.count != $1.phrase.count {
                    return $0.phrase.count > $1.phrase.count
                }
                return $0.canonical.count > $1.canonical.count
            }

        var result = text
        for candidate in candidates {
            guard let regex = try? NSRegularExpression(
                pattern: "(?i)(?<![@A-Za-z0-9_])"
                    + NSRegularExpression.escapedPattern(for: candidate.phrase)
                    + "(?![A-Za-z0-9_.])"
            ) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: "@" + NSRegularExpression.escapedTemplate(for: candidate.canonical))
        }
        return result
    }

    private static func candidates(for term: PersonalStore.Term) -> [Candidate] {
        guard let canonical = fileName(from: term.text) else { return [] }

        var phrases = [canonical, spokenPhrase(for: canonical)]
        // Explicit aliases are useful when ASR consistently renders a name
        // differently, but plain English aliases are too easy to over-tag.
        phrases += term.aliases.filter {
            $0.contains(".") || $0.lowercased().contains(" dot ")
        }

        var seen = Set<String>()
        return phrases.compactMap { phrase in
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return Candidate(phrase: trimmed, canonical: canonical)
        }
    }

    private static func fileName(from text: String) -> String? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("@") { candidate.removeFirst() }
        guard !candidate.isEmpty,
            !candidate.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "\\" }),
            candidate.contains(".")
        else { return nil }

        let extensionPart = candidate.split(separator: ".").last.map(String.init) ?? ""
        guard !extensionPart.isEmpty,
            extensionPart.count <= 8,
            extensionPart.allSatisfy({ $0.isLetter || $0.isNumber })
        else { return nil }
        return candidate
    }

    private static func spokenPhrase(for fileName: String) -> String {
        let characters = Array(fileName)
        var spaced = ""
        for index in characters.indices {
            let character = characters[index]
            let previous = index > characters.startIndex ? characters[index - 1] : nil
            let next = index < characters.index(before: characters.endIndex)
                ? characters[index + 1] : nil
            let startsAcronymTail = character.isUppercase
                && previous?.isUppercase == true && next?.isLowercase == true
            if character.isUppercase,
                previous?.isLowercase == true || previous?.isNumber == true || startsAcronymTail {
                spaced.append(" ")
            }
            spaced.append(character)
        }

        return spaced
            .replacingOccurrences(of: ".", with: " dot ")
            .replacingOccurrences(of: "_", with: " underscore ")
            .replacingOccurrences(of: "-", with: " dash ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
