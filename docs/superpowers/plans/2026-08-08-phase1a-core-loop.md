# Plynn Phase 1a — Reliable Core Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the spike into a daily-drivable dictation app: live streaming partials in a floating indicator, VAD silence gating, a tested session state machine (push-to-talk / double-tap hands-free / cancel / interruption), secure-input guard, and a menu bar presence.

**Architecture:** Rename spike targets to `PlynnKit`/`Plynn`. A pure, table-tested `Session` state machine emits `Effect`s; `AppDelegate` interprets effects against real subsystems (recorder, streaming transcriber, paster, indicator panel). Streaming uses FluidAudio's `StreamingModelVariant.parakeetUnified1120ms` (same model repo as the spike's batch path — no new download) with `setPartialTranscriptCallback` feeding the indicator. `VadManager` gates silence-only audio to kill hallucinations.

**Tech Stack:** Swift 6 / SPM, FluidAudio (StreamingAsrManager + VadManager), SwiftUI in NSPanel, NSStatusItem, Carbon `IsSecureEventInputEnabled`.

**Out of scope (Phase 1b):** permissions onboarding UI, model download progress, SpeechTranscriber instant-start fallback, settings window, launch-at-login, Sparkle.

**Exit criteria:** dictation with visible live partials; silence-only hold pastes nothing; fn+arrow never pastes; double-tap fn locks hands-free with Esc/tap-to-stop; no paste attempt while secure input is active; menu bar icon reflects state.

---

### Task 1: Rename targets Spike → real names

**Files:** `Package.swift`, `Sources/PlynnKit/*` (moved), `Sources/Plynn/main.swift` (moved), `Tests/PlynnKitTests/*` (moved), `scripts/make-app.sh`

- [ ] Step 1: `git mv Sources/PlynnSpikeKit Sources/PlynnKit && git mv Sources/PlynnSpike Sources/Plynn && git mv Tests/PlynnSpikeKitTests Tests/PlynnKitTests`
- [ ] Step 2: In `Package.swift` replace names: package `Plynn`, targets `PlynnKit`/`Plynn`/`PlynnKitTests`; executable target name `Plynn`. In test files replace `@testable import PlynnSpikeKit` → `@testable import PlynnKit`; in `main.swift` replace `import PlynnSpikeKit` → `import PlynnKit`. In `make-app.sh` replace `.build/release/PlynnSpike` → `.build/release/Plynn`.
- [ ] Step 3: `swift test 2>&1 | grep -cE "passed"` → all 5 tests pass. `./scripts/make-app.sh` → signed.
- [ ] Step 4: Commit `refactor: rename spike targets to Plynn/PlynnKit`.

### Task 2: Session state machine (pure TDD)

**Files:** Create `Sources/PlynnKit/Session.swift`, Test `Tests/PlynnKitTests/SessionTests.swift`

The heart of reliability. Pure value type — no timers, no I/O; time is passed in.

- [ ] Step 1: Write failing tests covering the full transition table:

```swift
import XCTest
@testable import PlynnKit

final class SessionTests: XCTestCase {
    var t0: ContinuousClock.Instant { ContinuousClock.now }

    func testPushToTalkHappyPath() {
        var s = Session()
        XCTAssertEqual(s.handle(.fnDown, at: t0), [.startRecording])
        XCTAssertEqual(s.handle(.fnUp, at: t0.advanced(by: .seconds(3))), [.stopAndTranscribe])
        XCTAssertEqual(s.handle(.transcriptReady("hi"), at: t0), [.paste("hi")])
        XCTAssertEqual(s.state, .idle)
    }

    func testInterruptedHoldDiscards() {
        var s = Session()
        _ = s.handle(.fnDown, at: t0)
        XCTAssertEqual(s.handle(.otherKeyDown, at: t0), [])
        XCTAssertEqual(s.handle(.fnUp, at: t0.advanced(by: .seconds(1))), [.discardRecording])
        XCTAssertEqual(s.state, .idle)
    }

    func testDoubleTapLocksHandsFree() {
        var s = Session()
        _ = s.handle(.fnDown, at: t0)
        _ = s.handle(.fnUp, at: t0.advanced(by: .milliseconds(150)))   // quick tap: too short → discard
        _ = s.handle(.fnDown, at: t0.advanced(by: .milliseconds(300))) // second tap within window
        XCTAssertEqual(s.state, .recording(.handsFree))
        // fn released in hands-free: keep recording
        XCTAssertEqual(s.handle(.fnUp, at: t0.advanced(by: .milliseconds(450))), [])
        XCTAssertEqual(s.state, .recording(.handsFree))
        // next single fn press stops it
        XCTAssertEqual(s.handle(.fnDown, at: t0.advanced(by: .seconds(5))), [.stopAndTranscribe])
    }

    func testEscapeCancelsRecordingAndTranscribing() {
        var s = Session()
        _ = s.handle(.fnDown, at: t0)
        XCTAssertEqual(s.handle(.escape, at: t0), [.discardRecording])
        _ = s.handle(.fnDown, at: t0); _ = s.handle(.fnUp, at: t0.advanced(by: .seconds(2)))
        XCTAssertEqual(s.state, .transcribing)
        XCTAssertEqual(s.handle(.escape, at: t0), [.cancelTranscription])
        XCTAssertEqual(s.handle(.transcriptReady("late"), at: t0), [])  // cancelled → no paste
    }

    func testEmptyTranscriptDoesNotPaste() {
        var s = Session()
        _ = s.handle(.fnDown, at: t0); _ = s.handle(.fnUp, at: t0.advanced(by: .seconds(2)))
        XCTAssertEqual(s.handle(.transcriptReady("  "), at: t0), [])
        XCTAssertEqual(s.state, .idle)
    }

    func testSecureInputBlocksSessionStart() {
        var s = Session()
        _ = s.handle(.secureInputChanged(true), at: t0)
        XCTAssertEqual(s.handle(.fnDown, at: t0), [])   // no recording in secure mode
        _ = s.handle(.secureInputChanged(false), at: t0)
        XCTAssertEqual(s.handle(.fnDown, at: t0), [.startRecording])
    }

    func testShortAccidentalTapDiscards() {
        var s = Session()
        _ = s.handle(.fnDown, at: t0)
        XCTAssertEqual(s.handle(.fnUp, at: t0.advanced(by: .milliseconds(150))), [.discardRecording])
    }
}
```

- [ ] Step 2: Run → FAIL (no `Session`).
- [ ] Step 3: Implement:

```swift
/// Pure dictation session state machine. All timing is injected via `at:`.
public struct Session: Sendable {
    public enum Mode: Equatable, Sendable { case pushToTalk, handsFree }
    public enum State: Equatable, Sendable {
        case idle, recording(Mode), transcribing, cancelled
    }
    public enum Event: Equatable, Sendable {
        case fnDown, fnUp, otherKeyDown, escape
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
            if on, case .recording = state { state = .idle; return [.discardRecording] }
            return []

        case (.idle, .fnDown):
            guard !secureInput else { return [] }
            if let up = lastQuickTapUp, now < up.advanced(by: Self.doubleTapWindow) {
                lastQuickTapUp = nil
                state = .recording(.handsFree)
                return []  // already recording since the quick tap kept audio? No: restart cleanly
                    + [.startRecording]
            }
            interrupted = false
            recordingStart = now
            state = .recording(.pushToTalk)
            return [.startRecording]

        case (.recording(.pushToTalk), .fnUp):
            let start = recordingStart ?? now
            if interrupted { state = .idle; return [.discardRecording] }
            if now < start.advanced(by: Self.minHold) {
                lastQuickTapUp = now
                state = .idle
                return [.discardRecording]
            }
            state = .transcribing
            return [.stopAndTranscribe]

        case (.recording(.handsFree), .fnUp):
            return []  // release doesn't stop a locked session

        case (.recording(.handsFree), .fnDown):
            state = .transcribing
            return [.stopAndTranscribe]

        case (.recording, .otherKeyDown):
            if case .recording(.pushToTalk) = state { interrupted = true }
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
```

Note the double-tap branch: fix the expression to a plain `return [.startRecording]` with `state = .recording(.handsFree)` (the `[] + [...]` sketch above is a reminder that the quick tap already discarded its audio — hands-free starts a fresh recording).

- [ ] Step 4: Run tests → all pass. Adjust transition details to make the table in Step 1 true; the tests are the spec.
- [ ] Step 5: Commit `feat: tested session state machine (PTT, hands-free double-tap, cancel, secure-input)`.

### Task 3: Streaming transcriber + VAD gate

**Files:** Create `Sources/PlynnKit/StreamingTranscriber.swift`, `Sources/PlynnKit/SilenceGate.swift`; Test `Tests/PlynnKitTests/StreamingTranscriberTests.swift`; fixture `silence.wav` added to `scripts/make-fixtures.sh`

- [ ] Step 1: Add a 3 s silence fixture: `sox -n -r 16000 -c 1 "$DIR/silence.wav" trim 0 3` if sox exists, else generate in-test with zeros (prefer in-test zeros — no new dependency).
- [ ] Step 2: Failing tests:

```swift
final class StreamingTranscriberTests: XCTestCase {
    func testStreamedFixtureProducesPartialsAndFinal() async throws {
        let st = StreamingTranscriber(variant: .parakeetUnified1120ms)
        try await st.start()
        nonisolated(unsafe) var partials: [String] = []
        await st.setPartialCallback { partials.append($0) }
        let samples = try AudioFile.loadSamples16kMono(
            url: Bundle.module.url(forResource: "Fixtures/hello.wav", withExtension: nil)!)
        for chunk in samples.chunks(of: 8_000) {     // feed 0.5 s at a time
            try await st.append(samples: Array(chunk))
        }
        let final = try await st.finish()
        XCTAssertTrue(final.lowercased().contains("hello"), "got: \(final)")
        XCTAssertFalse(partials.isEmpty, "expected live partials during streaming")
    }

    func testSilenceProducesEmptyTranscript() async throws {
        let st = StreamingTranscriber(variant: .parakeetUnified1120ms)
        try await st.start()
        try await st.append(samples: [Float](repeating: 0, count: 48_000))  // 3 s silence
        let final = try await st.finish()
        XCTAssertEqual(final.trimmingCharacters(in: .whitespacesAndNewlines), "",
                       "silence must not hallucinate text; got: '\(final)'")
    }
}
```

- [ ] Step 3: Implement `StreamingTranscriber` as an actor wrapping `StreamingModelVariant.createManager()`: `start()` = loadModels + reset; `append(samples:)` wraps samples in an `AVAudioPCMBuffer` (16 k mono float) then `appendAudio` + `processBufferedAudio`; `finish()` = manager.finish() **then SilenceGate check**; `setPartialCallback` forwards to `setPartialTranscriptCallback`. `SilenceGate`: run `VadManager().process(samples)` over the accumulated session audio at finish; if no `VadResult` marks speech, return `""` regardless of model output (kills silence hallucinations). Keep the spike's `Transcriber` for the final-accuracy re-pass later; export an `Array.chunks(of:)` helper in PlynnKit.
- [ ] Step 4: Tests pass (first run downloads the VAD model, small). Commit `feat: streaming transcriber with live partials + VAD silence gate`.

### Task 4: Audio level metering for the waveform

**Files:** Modify `Sources/PlynnKit/AudioRecorder.swift`; Test append to `Tests/PlynnKitTests/AudioFileTests.swift`

- [ ] Step 1: Failing test: `AudioLevel.rms(of: sineBuffer)` ≈ 0.707 for a full-scale sine; 0 for zeros.
- [ ] Step 2: Add `public enum AudioLevel { public static func rms(of samples: [Float]) -> Float }` (sqrt of mean square, no allocation) and extend `AudioRecorder` with `public var onChunk: (([Float]) -> Void)?` invoked from the tap with each converted chunk (samples feed BOTH the streaming transcriber and `AudioLevel.rms` for the UI).
- [ ] Step 3: Tests pass. Commit `feat: audio chunk callback + RMS metering`.

### Task 5: Floating indicator panel

**Files:** Create `Sources/PlynnKit/IndicatorPanel.swift`, `Sources/PlynnKit/IndicatorView.swift`

- [ ] Step 1: `IndicatorPanel`: NSPanel subclass — `.nonactivatingPanel, .borderless, .fullSizeContentView`; `canBecomeKey`/`canBecomeMain` → false; `.floating` level; `.canJoinAllSpaces, .fullScreenAuxiliary, .stationary`; clear background; hosts `IndicatorView` via `NSHostingView`; positions bottom-center of `NSScreen.main` (60 px up); `show()`/`hide()` with `orderFrontRegardless`.
- [ ] Step 2: `IndicatorView` (SwiftUI, observes an `@Observable IndicatorModel { var phase: Phase; var level: Float; var partial: String }`): capsule with subtle material background; content by phase — `.recording`: 5 animated bars scaled by `level` + partial text (last ~60 chars, mid-truncated); `.transcribing`: pulsing dots; `.handsFreeLocked`: adds a small lock glyph; `.secure`: red lock + "secure field". Keep it minimal — polish is Phase 4.
- [ ] Step 3: Build. Manual check deferred to Task 7's E2E. Commit `feat: non-activating floating indicator with waveform + live partials`.

### Task 6: Secure-input watcher

**Files:** Create `Sources/PlynnKit/SecureInputWatcher.swift`

- [ ] Step 1: Poll `IsSecureEventInputEnabled()` (Carbon) on a 1 s main-queue timer; `public var onChange: ((Bool) -> Void)?` fired on transitions only. (Logic worth testing lives in `Session`, already covered.)
- [ ] Step 2: Build. Commit `feat: secure input watcher`.

### Task 7: Wire it all + menu bar

**Files:** Rewrite `Sources/Plynn/main.swift`; extend `Sources/PlynnKit/HotkeyMonitor.swift` (escape key)

- [ ] Step 1: Extend `HotkeyMonitor` with `onEscape` (keyDown keycode 53) — only fires when a session is active (AppDelegate decides), and make sure Esc during recording ALSO sets `interrupted` semantics correctly (route through `Session`, which already handles it).
- [ ] Step 2: `AppDelegate` holds `Session` + subsystems; every hotkey/secure/transcript event goes through `session.handle(event, at: .now)` and the returned effects are interpreted: `startRecording` → recorder.start + streaming start + indicator.show(.recording); chunks → `st.append` + `model.level`/`model.partial`; `stopAndTranscribe` → recorder.stop + `st.finish()` → `.transcriptReady(text)`; `paste(text)` → `Paster.paste` + latency NSLog (keep the spike's metrics); `discardRecording` → recorder.stop discard + indicator.hide; `cancelTranscription` → indicator.hide. Hands-free stop also triggered by clicking the indicator capsule (send `.fnDown` equivalent event `.stopRequested` — add to Session with same handling as hands-free fnDown). NSStatusItem: template icon; states idle/recording/secure via symbol swap; menu = "Plynn vX — state", Separator, Quit (`q`).
- [ ] Step 3: `swift test` all green; `./scripts/make-app.sh`; launch.
- [ ] Step 4: Commit `feat: Phase 1a wired — streaming dictation with indicator and menu bar`.

### Task 8: E2E validation (Carlton)

- [ ] Dictate with live partials visible; confirm partial text updates while speaking.
- [ ] Hold fn silently 5 s → nothing pastes (VAD gate).
- [ ] fn+arrow → no paste. Esc mid-recording → cancels. Esc mid-transcription → no paste.
- [ ] Double-tap fn → hands-free (lock icon); Esc or fn stops; click capsule stops.
- [ ] Focus a password field (Safari) → indicator shows secure state; fn does nothing.
- [ ] Terminal "Secure Keyboard Entry" on → same, and recovers when off.
- [ ] Menu bar icon tracks state. RSS logged < 2 GB.
