import Foundation

/// Pure dictation session state machine. All timing is injected via `at:` so
/// every transition is unit-testable; the app layer interprets the returned
/// effects against real subsystems (recorder, transcriber, paster, indicator).
public struct Session: Sendable {
    public enum Mode: Equatable, Sendable { case pushToTalk, handsFree }
    public enum State: Equatable, Sendable {
        case idle, recording(Mode), transcribing, cancelled
        /// Long-running meeting capture (mic + system audio). Started and
        /// stopped by a triple-tap; individual fn presses are ignored so one
        /// stray key can never end a meeting.
        case meeting
    }
    public enum Event: Equatable, Sendable {
        case fnDown, fnUp, otherKeyDown, escape
        /// Stop initiated from UI (clicking the indicator capsule in hands-free,
        /// or the "Stop meeting" menu item).
        case stopRequested
        case transcriptReady(String)
        case secureInputChanged(Bool)
    }
    public enum Effect: Equatable, Sendable {
        case startRecording, stopAndTranscribe, discardRecording
        case cancelTranscription, paste(String)
        case startMeeting, stopMeeting
    }

    /// fnUp sooner than this after fnDown = accidental tap (or first half of a double-tap).
    public static let minHold: Duration = .milliseconds(250)
    /// Second fnDown within this window after a quick tap = hands-free lock.
    public static let doubleTapWindow: Duration = .milliseconds(400)

    public private(set) var state: State = .idle
    private var interrupted = false
    private var secureInput = false
    private var lastQuickTapUp: ContinuousClock.Instant?
    private var recordingStart: ContinuousClock.Instant?
    /// When hands-free locked (the second tap). A third fnDown inside the tap
    /// window of this instant is a triple-tap, not a stop.
    private var handsFreeLockedAt: ContinuousClock.Instant?

    public init() {}

    public mutating func handle(_ event: Event, at now: ContinuousClock.Instant) -> [Effect] {
        switch (state, event) {
        case (_, .secureInputChanged(let on)):
            secureInput = on
            if on, case .recording = state {
                state = .idle
                return [.discardRecording]
            }
            return []

        case (.idle, .fnDown):
            guard !secureInput else { return [] }
            if let up = lastQuickTapUp, now < up.advanced(by: Self.doubleTapWindow) {
                lastQuickTapUp = nil
                handsFreeLockedAt = now
                state = .recording(.handsFree)
                return [.startRecording]
            }
            lastQuickTapUp = nil
            interrupted = false
            recordingStart = now
            state = .recording(.pushToTalk)
            return [.startRecording]

        // Meeting: fn taps are inert unless they form a triple-tap. We reuse
        // the same quick-tap timing so "triple-tap" means the same thing
        // whether it starts or stops a meeting.
        case (.meeting, .fnDown):
            // Every press is a candidate quick tap, so fnUp can measure it.
            recordingStart = now
            if let up = lastQuickTapUp, now < up.advanced(by: Self.doubleTapWindow) {
                // Second quick tap; a third fnDown inside the window ends it.
                if let locked = handsFreeLockedAt,
                    now < locked.advanced(by: Self.doubleTapWindow) {
                    lastQuickTapUp = nil
                    handsFreeLockedAt = nil
                    state = .idle
                    return [.stopMeeting]
                }
                handsFreeLockedAt = now
                lastQuickTapUp = nil
                return []
            }
            handsFreeLockedAt = nil
            return []

        case (.meeting, .fnUp):
            let start = recordingStart ?? now
            if now < start.advanced(by: Self.minHold) {
                lastQuickTapUp = now
            }
            return []

        case (.meeting, .escape), (.meeting, .stopRequested):
            lastQuickTapUp = nil
            handsFreeLockedAt = nil
            state = .idle
            return [.stopMeeting]

        case (.recording(.pushToTalk), .fnUp):
            let start = recordingStart ?? now
            if interrupted {
                state = .idle
                return [.discardRecording]
            }
            if now < start.advanced(by: Self.minHold) {
                lastQuickTapUp = now  // may become the first half of a double-tap
                state = .idle
                return [.discardRecording]
            }
            state = .transcribing
            return [.stopAndTranscribe]

        case (.recording(.handsFree), .fnUp):
            return []  // release doesn't stop a locked session

        case (.recording(.handsFree), .fnDown):
            // A fast third tap right after the lock is a triple-tap → meeting.
            // The hands-free recording it interrupts is discarded, never pasted.
            if let locked = handsFreeLockedAt,
                now < locked.advanced(by: Self.doubleTapWindow) {
                handsFreeLockedAt = nil
                lastQuickTapUp = nil
                state = .meeting
                return [.discardRecording, .startMeeting]
            }
            handsFreeLockedAt = nil
            state = .transcribing
            return [.stopAndTranscribe]

        case (.recording(.handsFree), .stopRequested):
            handsFreeLockedAt = nil
            state = .transcribing
            return [.stopAndTranscribe]

        case (.recording(.pushToTalk), .otherKeyDown):
            interrupted = true  // fn+something = a shortcut, not dictation
            return []

        case (.recording, .escape):
            state = .idle
            return [.discardRecording]

        case (.transcribing, .escape):
            state = .cancelled
            return [.cancelTranscription]

        case (.transcribing, .transcriptReady(let text)):
            state = .idle
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [.paste(trimmed)]

        case (.cancelled, .transcriptReady):
            state = .idle
            return []

        default:
            return []
        }
    }
}
