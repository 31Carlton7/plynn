import XCTest
@testable import PlynnKit

final class PolishGateTests: XCTestCase {
    func testCleanShortTextSkipsLLM() {
        XCTAssertFalse(PolishGate.needsPolish("Ship it today"))
        XCTAssertFalse(PolishGate.needsPolish("Sounds good, see you at 3"))
        XCTAssertFalse(PolishGate.needsPolish("Can you review my PR?"))
    }

    func testFillerWordsTriggerPolish() {
        XCTAssertTrue(PolishGate.needsPolish("um ship it today"))
        XCTAssertTrue(PolishGate.needsPolish("so uh let's meet later"))
        XCTAssertTrue(PolishGate.needsPolish("it's you know kind of done"))
    }

    func testBacktrackMarkersTriggerPolish() {
        XCTAssertTrue(PolishGate.needsPolish("ship friday actually monday"))
        XCTAssertTrue(PolishGate.needsPolish("send it to Sam I mean Alex"))
        XCTAssertTrue(PolishGate.needsPolish("delete that scratch that keep it"))
    }

    func testEnumerationTriggersPolish() {
        XCTAssertTrue(PolishGate.needsPolish("first update the docs second fix the tests"))
    }

    func testLongDictationTriggersPolish() {
        let long = Array(repeating: "word", count: 25).joined(separator: " ")
        XCTAssertTrue(PolishGate.needsPolish(long))
    }

    func testFillerInsideWordDoesNotTrigger() {
        // "umbrella" contains "um"; "pumice" has "um"; must not trigger.
        XCTAssertFalse(PolishGate.needsPolish("bring the umbrella"))
        XCTAssertFalse(PolishGate.needsPolish("that pumice stone works"))
    }
}
