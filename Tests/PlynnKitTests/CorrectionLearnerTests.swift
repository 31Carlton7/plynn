import XCTest
@testable import PlynnKit

final class CorrectionLearnerTests: XCTestCase {
    func pairs(_ original: String, _ edited: String) -> [CorrectionLearner.Correction] {
        CorrectionLearner.corrections(original: original, edited: edited)
    }

    func testLearnsSingleWordFix() {
        let found = pairs("I built plin last week", "I built Plynn last week")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].heard, "plin")
        XCTAssertEqual(found[0].corrected, "Plynn")
    }

    func testIgnoresContentEdits() {
        // monday → tuesday is a meaning change, not an ASR miss.
        XCTAssertTrue(pairs("ship on monday", "ship on tuesday").isEmpty)
    }

    func testIgnoresPureCaseChanges() {
        // Casing the same word differently isn't worth a dictionary entry.
        XCTAssertTrue(pairs("use plynn here", "use Plynn here").isEmpty)
    }

    func testLearnsMultipleFixes() {
        let found = pairs(
            "tell akins about plin",
            "tell Aikins about Plynn")
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains { $0.heard == "akins" && $0.corrected == "Aikins" })
        XCTAssertTrue(found.contains { $0.heard == "plin" && $0.corrected == "Plynn" })
    }

    func testIgnoresInsertionsAndDeletions() {
        XCTAssertTrue(pairs("ship it", "ship it now please").isEmpty)
        XCTAssertTrue(pairs("ship it now please", "ship it").isEmpty)
    }

    func testIgnoresShortTokens() {
        // "a" → "I" style single-char noise never learns.
        XCTAssertTrue(pairs("a think so", "I think so").isEmpty)
    }

    func testIgnoresCompletelyDifferentText() {
        XCTAssertTrue(pairs("hello world", "unrelated reply typed later").isEmpty)
    }

    func testPunctuationAdjacent() {
        let found = pairs("meet at charm tecnologies.", "meet at Charm Technologies.")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].heard, "tecnologies")
        XCTAssertEqual(found[0].corrected, "Technologies")
    }
}
