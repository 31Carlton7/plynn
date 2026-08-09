import XCTest
@testable import PlynnKit

final class TransformPromptTests: XCTestCase {
    func testPromptCarriesTextAndInstruction() {
        let p = TransformPrompt.build(
            selectedText: "The quick brown fox jumps over the lazy dog.",
            instruction: "make this shorter")
        XCTAssertTrue(p.contains("<text>"))
        XCTAssertTrue(p.contains("The quick brown fox"))
        XCTAssertTrue(p.contains("<instruction>"))
        XCTAssertTrue(p.contains("make this shorter"))
        XCTAssertTrue(p.contains("ONLY"))  // output-only rule present
    }

    func testSanitizeSharedGuards() {
        // Same guards as polish: empty/nil output falls back to the input.
        XCTAssertEqual(PolishPrompt.sanitize(nil, input: "keep"), "keep")
        XCTAssertEqual(PolishPrompt.sanitize("  ", input: "keep"), "keep")
        XCTAssertEqual(PolishPrompt.sanitize("\"quoted\"", input: "x"), "quoted")
    }

    func testRunawayGuardScalesWithSelection() {
        // A transform of a long selection may legitimately return long text —
        // but 10x the input is a runaway.
        let input = String(repeating: "word ", count: 40)
        let runaway = String(repeating: "word ", count: 400)
        XCTAssertEqual(PolishPrompt.sanitize(runaway, input: input), input)
    }
}
