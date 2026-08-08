import XCTest
@testable import PlynnKit

final class RulesFormatterTests: XCTestCase {
    func fmt(_ s: String) -> RulesFormatter.Result { RulesFormatter.format(s) }

    func testSpokenPeriodAndCapitalization() {
        XCTAssertEqual(fmt("hello world period how are you").text, "Hello world. How are you")
    }

    func testCommaAndQuestionMark() {
        XCTAssertEqual(fmt("wait comma what question mark").text, "Wait, what?")
    }

    func testExclamationVariants() {
        XCTAssertEqual(fmt("wow exclamation point").text, "Wow!")
        XCTAssertEqual(fmt("wow exclamation mark").text, "Wow!")
    }

    func testNewLineAndParagraph() {
        XCTAssertEqual(fmt("first line new line second line").text, "First line\nSecond line")
        XCTAssertEqual(fmt("intro new paragraph body").text, "Intro\n\nBody")
        XCTAssertEqual(fmt("a next line b").text, "A\nB")
    }

    func testCapitalizesAfterNewline() {
        XCTAssertEqual(fmt("first new line second period third").text, "First\nSecond. Third")
    }

    func testPressEnterStrippedAndFlagged() {
        let r = fmt("ship it press enter")
        XCTAssertEqual(r.text, "Ship it")
        XCTAssertTrue(r.pressEnter)
        let r2 = fmt("done hit enter")
        XCTAssertEqual(r2.text, "Done")
        XCTAssertTrue(r2.pressEnter)
        XCTAssertFalse(fmt("press enter to continue is the label").pressEnter)  // not trailing
    }

    func testModelAttachedPunctuationOnCommandWord() {
        // Parakeet often emits "period." for the spoken word — must not double up.
        XCTAssertEqual(fmt("one period. two period.").text, "One. Two.")
        XCTAssertEqual(fmt("hey comma, you").text, "Hey, you")
    }

    func testEmDashAndColonAndSemicolon() {
        XCTAssertEqual(fmt("note colon it works semicolon mostly").text, "Note: it works; mostly")
        XCTAssertEqual(fmt("thought em dash interrupted").text, "Thought — interrupted")
    }

    func testNoCommandsPassthrough() {
        XCTAssertEqual(fmt("This already reads fine.").text, "This already reads fine.")
    }

    func testWhitespaceNormalization() {
        XCTAssertEqual(fmt("  spaced   out  period  ").text, "Spaced out.")
    }
}
