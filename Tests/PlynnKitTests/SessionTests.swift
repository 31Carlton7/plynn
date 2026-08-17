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

    // MARK: Triple-tap → meeting

    /// tap, tap (locks hands-free), tap quickly → becomes a meeting instead.
    /// The hands-free recording that the second tap started must be discarded,
    /// never transcribed and pasted.
    func testTripleTapStartsMeetingAndDiscardsHandsFree() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(100)))
        XCTAssertEqual(s.handle(.fnDown, at: start.advanced(by: .milliseconds(250))), [.startRecording])
        XCTAssertEqual(s.state, .recording(.handsFree))
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(350)))
        // third tap, still inside the window → meeting
        XCTAssertEqual(
            s.handle(.fnDown, at: start.advanced(by: .milliseconds(500))),
            [.discardRecording, .startMeeting])
        XCTAssertEqual(s.state, .meeting)
        // releasing fn during a meeting changes nothing
        XCTAssertEqual(s.handle(.fnUp, at: start.advanced(by: .milliseconds(600))), [])
        XCTAssertEqual(s.state, .meeting)
    }

    /// Regression guard: a deliberate single fn press well after the lock still
    /// stops hands-free (the pre-existing behaviour) — only a *fast* third tap
    /// escalates to a meeting.
    func testSlowThirdPressStillStopsHandsFree() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(100)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(250)))
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(350)))
        XCTAssertEqual(s.handle(.fnDown, at: start.advanced(by: .seconds(5))), [.stopAndTranscribe])
        XCTAssertEqual(s.state, .transcribing)
    }

    /// Triple-tap during a meeting stops it. Individual fn presses do not —
    /// a meeting must never end because of one stray key.
    func testTripleTapStopsMeeting() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(100)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(250)))
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(350)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(500)))
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(600)))
        XCTAssertEqual(s.state, .meeting)

        // Ten minutes in: a single press does nothing.
        let later = start.advanced(by: .seconds(600))
        XCTAssertEqual(s.handle(.fnDown, at: later), [])
        XCTAssertEqual(s.handle(.fnUp, at: later.advanced(by: .milliseconds(100))), [])
        XCTAssertEqual(s.state, .meeting)
        // ...but a triple-tap ends it.
        _ = s.handle(.fnDown, at: later.advanced(by: .milliseconds(250)))
        _ = s.handle(.fnUp, at: later.advanced(by: .milliseconds(350)))
        XCTAssertEqual(s.handle(.fnDown, at: later.advanced(by: .milliseconds(500))), [.stopMeeting])
        XCTAssertEqual(s.state, .idle)
    }

    /// Escape during a meeting also stops it — but keeps the recording.
    /// (Escape *discards* a dictation; a meeting is too valuable to lose.)
    func testEscapeStopsMeetingWithoutDiscarding() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(100)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(250)))
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(350)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(500)))
        XCTAssertEqual(s.state, .meeting)
        XCTAssertEqual(s.handle(.escape, at: start.advanced(by: .seconds(60))), [.stopMeeting])
        XCTAssertEqual(s.state, .idle)
    }

    /// Menu-bar "Stop meeting" (mouse) must work too.
    func testStopRequestedStopsMeeting() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(100)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(250)))
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(350)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(500)))
        XCTAssertEqual(s.handle(.stopRequested, at: start.advanced(by: .seconds(60))), [.stopMeeting])
        XCTAssertEqual(s.state, .idle)
    }

    /// Secure input discards a *dictation* (it exists to keep text out of
    /// password fields). A meeting never pastes, so a password prompt appearing
    /// mid-call must not kill the recording.
    func testSecureInputDoesNotStopMeeting() {
        var s = Session()
        let start = t0
        _ = s.handle(.fnDown, at: start)
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(100)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(250)))
        _ = s.handle(.fnUp, at: start.advanced(by: .milliseconds(350)))
        _ = s.handle(.fnDown, at: start.advanced(by: .milliseconds(500)))
        XCTAssertEqual(s.state, .meeting)
        XCTAssertEqual(s.handle(.secureInputChanged(true), at: start.advanced(by: .seconds(30))), [])
        XCTAssertEqual(s.state, .meeting)
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
