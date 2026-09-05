import XCTest
@testable import PlynnKit

final class PolishPromptTests: XCTestCase {
    private let glossary = ["Jay", "Kerry", "Lyle", "Neo", "OAUTH", "SMU", "npm"]
    private let spoken = "Realm needs custom access so we can run commands without asking again."

    // MARK: sanitize — glossary echo

    /// The reported bug: the polish model appended the preferred-spellings
    /// list to the cleaned text as a bulleted block.
    func testStripsEchoedGlossaryList() {
        let leaked = """
            Realm needs custom access so we can run commands without asking again.

            - Jay
            - Kerry
            - Lyle
            - Neo
            - OAUTH
            - SMU
            - npm
            """
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    func testStripsEchoedGlossaryWithoutBullets() {
        let leaked = spoken + "\n\nJay\nKerry\nnpm"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    func testStripsCommaSeparatedGlossaryLine() {
        let leaked = spoken + "\n\nJay, Kerry, npm"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    func testStripsNumberedGlossaryList() {
        let leaked = spoken + "\n\n1. Jay\n2. Kerry"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: spoken, glossary: glossary), spoken)
    }

    /// Only the trailing block goes — real content above it must survive intact.
    func testKeepsBodyAboveTheEchoedList() {
        let body = "First line of the note.\nSecond line of the note."
        XCTAssertEqual(
            PolishPrompt.sanitize(body + "\n\n- Jay\n- npm", input: body, glossary: glossary),
            body)
    }

    /// A term the speaker actually dictated is legitimate output, not an echo.
    func testKeepsGlossaryTermsTheSpeakerActuallySaid() {
        let input = "the ones to ping are\nJay\nKerry"
        XCTAssertEqual(
            PolishPrompt.sanitize(input, input: input, glossary: glossary), input)
    }

    /// The echoed list usually contains at least one term the speaker DID say —
    /// `relevantTerms` picks terms near transcript words, and the dictionary
    /// pass has already spelled the spoken ones canonically. Exempting those
    /// per-line left the rest of the list standing.
    func testStripsMixedEchoWhenSomeTermsWereSpoken() {
        let said = "Ask Jay whether the release is ready."
        let leaked = said + "\n\n- Jay\n- Kerry\n- npm"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: said, glossary: glossary), said)
    }

    /// Same leak on one comma-separated line: a spoken term first meant the
    /// whole line failed the all-unspoken test and nothing was stripped.
    func testStripsMixedCommaSeparatedEchoLedBySpokenTerm() {
        let said = "Ask Jay whether the release is ready."
        let leaked = said + "\n\nJay, Kerry, npm"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: said, glossary: glossary), said)
    }

    func testKeepsTextWithNoGlossaryTail() {
        let clean = "Ship the release on Monday."
        XCTAssertEqual(
            PolishPrompt.sanitize(clean, input: clean, glossary: glossary), clean)
    }

    /// Output that is nothing but the glossary is unusable — fall back to input.
    func testAllGlossaryOutputFallsBackToInput() {
        XCTAssertEqual(
            PolishPrompt.sanitize("- Jay\n- Kerry\n- npm", input: spoken, glossary: glossary),
            spoken)
    }

    func testEmptyGlossaryLeavesOutputUntouched() {
        let text = "Jay\nKerry"
        XCTAssertEqual(PolishPrompt.sanitize(text, input: spoken, glossary: []), text)
    }

    // MARK: sanitize — appended recap list

    func testStripsAppendedTodoListRepeatedFromProse() {
        let input = """
            Whenever you're done with everything, use the D-slop skill over all of the PRs. Make sure that we have clean code written, then consolidate everything and merge it to the main code base. Release the new release and install it on my machine. Make sure everything works as intended.
            """
        let leaked = input + """


            - Use the D-slop skill over all of the PRs
            - Make sure that we have clean code written
            - Consolidate everything and merge it to the main code base
            - Release the new release and install it on my machine
            - Make sure everything works as intended
            """
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: input, removeRepeatedTrailingList: true),
            input)
    }

    func testStripsNumberedRecapRepeatedFromProse() {
        let body = "Review the changes. Run the tests."
        let leaked = body + "\n\n1. Review the changes\n2. Run the tests"
        XCTAssertEqual(
            PolishPrompt.sanitize(leaked, input: body, removeRepeatedTrailingList: true),
            body)
    }

    func testKeepsStandaloneDictatedList() {
        let list = "- Review the changes\n- Run the tests"
        XCTAssertEqual(
            PolishPrompt.sanitize(
                list, input: "first review the changes second run the tests",
                removeRepeatedTrailingList: true),
            list)
    }

    func testKeepsTrailingListWithNewContent() {
        let text = "Here is the plan.\n\n- Review the changes\n- Run the tests"
        XCTAssertEqual(
            PolishPrompt.sanitize(text, input: text, removeRepeatedTrailingList: true),
            text)
    }

    func testSharedSanitizerKeepsIntentionalTransformList() {
        let selection = "Review the changes. Run the tests."
        let transformed = selection + "\n\n- Review the changes\n- Run the tests"
        XCTAssertEqual(PolishPrompt.sanitize(transformed, input: selection), transformed)
    }

    // MARK: existing sanitize behavior still holds

    func testStillUnquotesAndFallsBackOnRunaway() {
        XCTAssertEqual(PolishPrompt.sanitize("\"hello there\"", input: "hello there"), "hello there")
        XCTAssertEqual(PolishPrompt.sanitize("", input: "keep me"), "keep me")
        XCTAssertEqual(PolishPrompt.sanitize(nil, input: "keep me"), "keep me")
    }

    // MARK: prompt shape

    /// A trailing word list reads as a cue to emit one, so the glossary must
    /// never be the last thing the model sees.
    func testOutputOnlyRuleIsTheFinalInstruction() {
        let p = PolishPrompt.instructions(
            tone: .neutral, technical: true, preferredSpellings: glossary)
        XCTAssertTrue(
            p.hasSuffix("- Output ONLY the cleaned text, nothing else."), "got tail: \(p.suffix(80))")
        XCTAssertTrue(p.contains("<glossary>"))
        XCTAssertTrue(p.contains("Never list, repeat, or append"))
        XCTAssertTrue(p.contains("Never append a summary"))
    }

    func testNoGlossarySectionWhenNoSpellings() {
        let p = PolishPrompt.instructions(tone: .casual, technical: false)
        XCTAssertFalse(p.contains("<glossary>"))
        XCTAssertTrue(p.hasSuffix("- Output ONLY the cleaned text, nothing else."))
    }
}
