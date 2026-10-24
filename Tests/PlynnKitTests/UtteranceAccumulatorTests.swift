import XCTest
@testable import PlynnKit

/// Result sequences captured from the on-device recognizer on macOS 15.
final class UtteranceAccumulatorTests: XCTestCase {
    private func stitch(_ events: [(String, Int, Bool, Bool)]) -> String {
        var acc = UtteranceAccumulator()
        for (text, segments, closed, isFinal) in events {
            acc.update(text: text, segmentCount: segments, closed: closed, isFinal: isFinal)
        }
        return acc.text
    }

    private let p1 = "The first idea is that bundles are being sold at a much lower price than the individual cards"
    private let p2 = "The second problem is that streamers do not have enough time to list everything"

    func testPausesKeepEveryUtterance() {
        // After ~2 s of silence the recognizer restarts and its final result
        // holds only the last utterance ("Yeah").
        XCTAssertEqual(stitch([
            ("The", 1, false, false), ("The first", 2, false, false),
            ("The first idea is that bundles", 6, false, false),
            (p1, 18, false, false), (p1, 18, true, false),
            ("The", 1, false, false), ("The second", 2, false, false),
            (p2, 14, false, false), (p2, 14, true, false),
            ("Yeah", 1, false, true),
        ]), "\(p1) \(p2) Yeah")
    }

    func testLastWordOnlyInFinal() {
        XCTAssertEqual(stitch([
            ("This is one continuous sentence with no pause at all before", 11, false, false),
            ("This is one continuous sentence with no pause at all before the end", 13, false, true),
        ]), "This is one continuous sentence with no pause at all before the end")
    }

    func testFinalRepeatingClosedUtteranceIsNotDuplicated() {
        XCTAssertEqual(stitch([
            ("Send it tomorrow", 3, false, false), ("Send it tomorrow", 3, true, false),
            ("Send it tomorrow", 3, false, true),
        ]), "Send it tomorrow")
    }

    func testRestartWithoutCloseSignal() {
        XCTAssertEqual(stitch([
            (p1, 18, false, false), ("The", 1, false, false), (p2, 14, false, true),
        ]), "\(p1) \(p2)")
    }

    func testRevisionAfterCloseExtendsUtterance() {
        XCTAssertEqual(stitch([
            ("Meet at three", 3, true, false), ("Meet at three thirty", 4, false, true),
        ]), "Meet at three thirty")
    }

    func testSmallRevisionIsNotARestart() {
        XCTAssertEqual(stitch([
            ("I want to go there", 5, false, false), ("I wanna go there", 4, false, false),
            ("I wanna go there now", 5, false, true),
        ]), "I wanna go there now")
    }
}
