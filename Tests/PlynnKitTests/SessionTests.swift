import XCTest
@testable import PlynnKit

final class SessionTests: XCTestCase {
    var t0: ContinuousClock.Instant { ContinuousClock.now }

    func testPushToTalkHappyPath() {
        var s = Session()
        let start = t0
        XCTAssertEqual(s.handle(.fnDown, at: start), [.startRecording])
        XCTAssertEqual(s.handle(.fnUp, at: start.advanced(by: .seconds(3))), [.stopAndTranscribe])
        XCTAssertEqual(s.handle(.transcriptReady("hi"), at: start), [.paste("hi")])
        XCTAssertEqual(s.state, .idle)
    }

    func testInterruptedHoldDiscards() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        XCTAssertEqual(s.handle(.otherKeyDown, at: start), [])
        XCTAssertEqual(s.handle(.fnUp, at: start.advanced(by: .seconds(1))), [.discardRecording])
        XCTAssertEqual(s.state, .idle)
    }

    func testDoubleTapLocksHandsFree() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        // quick tap: too short → discard, remembered as first half of a double-tap
        XCTAssertEqual(s.handle(.fnUp, at: start.advanced(by: .milliseconds(150))), [.discardRecording])
        // second tap within window → hands-free lock, fresh recording
        XCTAssertEqual(s.handle(.fnDown, at: start.advanced(by: .milliseconds(300))), [.startRecording])
        XCTAssertEqual(s.state, .recording(.handsFree))
        // fn released in hands-free: keep recording
        XCTAssertEqual(s.handle(.fnUp, at: start.advanced(by: .milliseconds(450))), [])
        XCTAssertEqual(s.state, .recording(.handsFree))
        // next single fn press stops it
        XCTAssertEqual(s.handle(.fnDown, at: start.advanced(by: .seconds(5))), [.stopAndTranscribe])
        XCTAssertEqual(s.state, .transcribing)
    }

    func testSlowSecondTapDoesNotLockHandsFree() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(150)))
        // second tap AFTER the window → normal push-to-talk
        XCTAssertEqual(s.handle(.fnDown, at: start.advanced(by: .seconds(2))), [.startRecording])
        XCTAssertEqual(s.state, .recording(.pushToTalk))
    }

    func testEscapeCancelsRecordingAndTranscribing() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        XCTAssertEqual(s.handle(.escape, at: start), [.discardRecording])
        XCTAssertEqual(s.state, .idle)
        _ = s.handle(.fnDown, at: start.advanced(by: .seconds(1)))
        _ = s.handle(.fnUp, at: start.advanced(by: .seconds(3)))
        XCTAssertEqual(s.state, .transcribing)
        XCTAssertEqual(s.handle(.escape, at: start), [.cancelTranscription])
        XCTAssertEqual(s.handle(.transcriptReady("late"), at: start), [])  // cancelled → no paste
        XCTAssertEqual(s.state, .idle)
    }

    func testEmptyTranscriptDoesNotPaste() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .seconds(2)))
        XCTAssertEqual(s.handle(.transcriptReady("  "), at: start), [])
        XCTAssertEqual(s.state, .idle)
    }

    func testSecureInputBlocksSessionStart() {
        var s = Session()
        let start = t0
        _ = s.handle(.secureInputChanged(true), at: start)
        XCTAssertEqual(s.handle(.fnDown, at: start), [])   // no recording in secure mode
        _ = s.handle(.secureInputChanged(false), at: start)
        XCTAssertEqual(s.handle(.fnDown, at: start), [.startRecording])
    }

    func testSecureInputMidRecordingDiscards() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        XCTAssertEqual(s.handle(.secureInputChanged(true), at: start), [.discardRecording])
        XCTAssertEqual(s.state, .idle)
    }

    func testShortAccidentalTapDiscards() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        XCTAssertEqual(s.handle(.fnUp, at: start.advanced(by: .milliseconds(150))), [.discardRecording])
        XCTAssertEqual(s.state, .idle)
    }

    func testStopRequestedStopsHandsFree() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(100)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(250)))  // hands-free
        XCTAssertEqual(s.state, .recording(.handsFree))
        XCTAssertEqual(s.handle(.stopRequested, at: start.advanced(by: .seconds(4))), [.stopAndTranscribe])
        XCTAssertEqual(s.state, .transcribing)
    }
}
