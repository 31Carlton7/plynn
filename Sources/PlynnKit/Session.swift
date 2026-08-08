import Foundation

/// Pure dictation session state machine. All timing is injected via `at:` so
/// every transition is unit-testable; the app layer interprets the returned
/// effects against real subsystems (recorder, transcriber, paster, indicator).
public struct Session: Sendable {
    public enum Mode: Equatable, Sendable { case pushToTalk, handsFree }
    public enum State: Equatable, Sendable {
        case idle, recording(Mode), transcribing, cancelled
    }
    public enum Event: Equatable, Sendable {
        case fnDown, fnUp, otherKeyDown, escape
        /// Stop initiated from UI (clicking the indicator capsule in hands-free).
        case stopRequested
        case transcriptReady(String)
        case secureInputChanged(Bool)
    }
    public enum Effect: Equatable, Sendable {
        case startRecording, stopAndTranscribe, discardRecording
        case cancelTranscription, paste(String)
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
                state = .recording(.handsFree)
                return [.startRecording]
            }
            lastQuickTapUp = nil
            interrupted = false
            recordingStart = now
            state = .recording(.pushToTalk)
            return [.startRecording]

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

        case (.recording(.handsFree), .fnDown),
            (.recording(.handsFree), .stopRequested):
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
