import XCTest
@testable import PlynnKit

final class TextPersonalizerTests: XCTestCase {
    // MARK: SnippetExpander

    let email = PersonalStore.Snippet(
        id: 1, trigger: "my email", expansion: "carlton@charmtechnologies.co")
    let addr = PersonalStore.Snippet(
        id: 2, trigger: "my address", expansion: "123 Main St, Boston MA")

    func testExpandsTriggerPhrase() {
        XCTAssertEqual(
            SnippetExpander.expand("Send it to my email please", snippets: [email]),
            "Send it to carlton@charmtechnologies.co please")
    }

    func testCaseInsensitiveTrigger() {
        XCTAssertEqual(
            SnippetExpander.expand("My Email is the best way", snippets: [email]),
            "carlton@charmtechnologies.co is the best way")
    }

    func testTriggerWithAdjacentPunctuation() {
        XCTAssertEqual(
            SnippetExpander.expand("Use my email.", snippets: [email]),
            "Use carlton@charmtechnologies.co.")
    }

    func testNoPartialWordMatch() {
        // "my emailing" must not trigger "my email"
        XCTAssertEqual(
            SnippetExpander.expand("my emailing habit", snippets: [email]),
            "my emailing habit")
    }

    func testMultipleSnippets() {
        XCTAssertEqual(
            SnippetExpander.expand("Ship to my address from my email", snippets: [email, addr]),
            "Ship to 123 Main St, Boston MA from carlton@charmtechnologies.co")
    }

    func testNoSnippetsNoChange() {
        XCTAssertEqual(SnippetExpander.expand("hello world", snippets: []), "hello world")
    }

    // MARK: DictionaryCorrector

    let plynn = PersonalStore.Term(id: 1, text: "Plynn", aliases: ["plin", "plyn"])
    let aikins = PersonalStore.Term(id: 2, text: "Aikins", aliases: ["akins", "aikens"])

    func testCorrectsAlias() {
        XCTAssertEqual(
            DictionaryCorrector.correct("I built plin last week", terms: [plynn]),
            "I built Plynn last week")
    }

    func testCorrectsCaseInsensitively() {
        XCTAssertEqual(
            DictionaryCorrector.correct("Plin is great", terms: [plynn]),
            "Plynn is great")
    }

    func testWholeWordOnly() {
        // "plinth" must not become "Plynnth"
        XCTAssertEqual(
            DictionaryCorrector.correct("a plinth stands", terms: [plynn]),
            "a plinth stands")
    }

    func testCanonicalCasingEnforced() {
        // The canonical text itself, wrongly cased, gets fixed too.
        XCTAssertEqual(
            DictionaryCorrector.correct("plynn is my app", terms: [plynn]),
            "Plynn is my app")
    }

    func testMultipleTermsAndPunctuation() {
        XCTAssertEqual(
            DictionaryCorrector.correct("Tell akins about plyn.", terms: [plynn, aikins]),
            "Tell Aikins about Plynn.")
    }

    func testNoTermsNoChange() {
        XCTAssertEqual(DictionaryCorrector.correct("nothing here", terms: []), "nothing here")
    }

    func testCommonWordAliasIsInert() {
        // Imported data can carry aliases like "plan" → replacing every real
        // "plan" would corrupt dictations; common-word aliases must be skipped.
        let term = PersonalStore.Term(id: 3, text: "plynn", aliases: ["plan"])
        XCTAssertEqual(
            DictionaryCorrector.correct(
                "let's make a plan", terms: [term], commonWords: ["plan", "the", "make"]),
            "let's make a plan")
    }

    func testRareAliasStillCorrectsWithGuard() {
        let term = PersonalStore.Term(id: 1, text: "Plynn", aliases: ["plin"])
        XCTAssertEqual(
            DictionaryCorrector.correct(
                "I built plin today", terms: [term], commonWords: ["plan", "built"]),
            "I built Plynn today")
    }

    // MARK: relevantTerms (LLM prompt cap)

    func testRelevantTermsMatchesNearMisses() {
        let terms = [plynn, aikins, PersonalStore.Term(id: 9, text: "Kubernetes", aliases: [])]
        let relevant = DictionaryCorrector.relevantTerms(
            for: "we shipped plynne to production", terms: terms)
        XCTAssertEqual(relevant, ["Plynn"])
    }

    func testRelevantTermsEmptyWhenNothingClose() {
        XCTAssertTrue(
            DictionaryCorrector.relevantTerms(for: "hello world", terms: [plynn, aikins]).isEmpty)
    }

    func testRelevantTermsMatchesAliases() {
        let relevant = DictionaryCorrector.relevantTerms(for: "ping akins now", terms: [aikins])
        XCTAssertEqual(relevant, ["Aikins"])
    }

    /// Regression: a flat edit distance of 2 made every short term "relevant"
    /// to every transcript — "SWE" is two edits from "the", "npm" from "app" —
    /// so the whole dictionary rode along in the polish prompt.
    func testRelevantTermsIgnoresShortTermsTwoEditsFromCommonWords() {
        let shortTerms = ["Jay", "Neo", "SMU", "SWE", "Sid", "Sri", "Yaw", "npm", "n8n"]
            .enumerated()
            .map { PersonalStore.Term(id: Int64($0.offset + 20), text: $0.element, aliases: []) }
        let transcript =
            "Realm needs custom access with the macOS CLI so we are able to run "
            + "any commands from it without having to ask for permissions again"
        XCTAssertTrue(
            DictionaryCorrector.relevantTerms(for: transcript, terms: shortTerms).isEmpty,
            "short terms matched common words: "
                + DictionaryCorrector.relevantTerms(for: transcript, terms: shortTerms)
                    .joined(separator: ", "))
    }

    func testRelevantTermsStillMatchesShortTermAtOneEdit() {
        let term = PersonalStore.Term(id: 30, text: "n8n", aliases: [])
        XCTAssertEqual(
            DictionaryCorrector.relevantTerms(for: "wire it up in nan today", terms: [term]),
            ["n8n"])
    }

    func testRelevantTermsCapsListLength() {
        let terms = (0..<40).map {
            PersonalStore.Term(id: Int64($0), text: "Kubernetes\($0)", aliases: [])
        }
        XCTAssertLessThanOrEqual(
            DictionaryCorrector.relevantTerms(for: "kubernetes1 deploy", terms: terms).count, 12)
    }
}
