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
}
