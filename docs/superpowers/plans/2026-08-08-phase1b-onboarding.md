# Plynn Phase 1b — Onboarding, Engine Fallback & Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Plynn installable by a stranger: a permissions onboarding checklist, dictation that works instantly via Apple's SpeechTranscriber while Parakeet downloads in the background (with progress), auto-switch to Parakeet when ready, a minimal settings window, and launch-at-login.

**Architecture:** A `DictationEngine` protocol abstracts `StreamingTranscriber` (Parakeet) and a new `AppleSpeechEngine` (SpeechAnalyzer/SpeechTranscriber, macOS 26). `EngineManager` owns selection: preferred engine when its models are present, fallback otherwise, publishing download progress. Onboarding + Settings are SwiftUI windows; permissions are polled (no notification APIs exist).

**Tech Stack:** Swift 6 / SPM, Speech.framework (SpeechAnalyzer), FluidAudio ProgressHandler, SMAppService, AVCaptureDevice/AXIsProcessTrusted polling.

**Deferred:** Sparkle auto-update (needs hosted appcast — release prep, Phase 4). History UI (Phase 3).

**Exit criteria:** fresh-user flow works: launch → onboarding checklist → grant → dictate immediately (Apple engine) → Parakeet finishes downloading → seamless engine switch; settings window with launch-at-login + engine picker; all automated tests green.

---

### Task 1: DictationEngine protocol

**Files:** Create `Sources/PlynnKit/DictationEngine.swift`; modify `StreamingTranscriber.swift`, `Sources/Plynn/main.swift`; Test: existing streaming tests must stay green.

- [ ] Step 1: Protocol mirroring StreamingTranscriber's surface:

```swift
public protocol DictationEngine: Actor {
    var displayName: String { get }
    /// Load whatever the engine needs (idempotent) and reset for a new session.
    func start() async throws
    func setPartialCallback(_ callback: @escaping @Sendable (String) -> Void) async
    func append(samples: [Float]) async throws
    /// Final transcript — empty string when nothing usable was said.
    func finish() async throws -> String
}
```

- [ ] Step 2: `extension StreamingTranscriber: DictationEngine` (add `displayName` = "Parakeet (local)"). AppDelegate references `any DictationEngine` instead of the concrete type. `swift test` green. Commit `refactor: DictationEngine protocol`.

### Task 2: AppleSpeechEngine (SpeechTranscriber fallback, TDD)

**Files:** Create `Sources/PlynnKit/AppleSpeechEngine.swift`; Test `Tests/PlynnKitTests/AppleSpeechEngineTests.swift`

- [ ] Step 1: Failing test (mirrors the streaming tests; `XCTSkip` when the locale asset can't be ensured so CI without the model stays green):

```swift
func testTranscribesFixture() async throws {
    let engine = AppleSpeechEngine()
    do { try await engine.start() }
    catch AppleSpeechEngine.EngineError.assetUnavailable { throw XCTSkip("en asset unavailable") }
    let samples = try AudioFile.loadSamples16kMono(url: /* hello.wav */)
    for chunk in samples.chunks(of: 8_000) { try await engine.append(samples: Array(chunk)) }
    let final = try await engine.finish()
    XCTAssertTrue(final.lowercased().contains("hello"), "got: \(final)")
}
```

- [ ] Step 2: Implement actor `AppleSpeechEngine: DictationEngine`:
  - `start()`: build `SpeechTranscriber(locale: .en_US-ish current, …, reportingOptions: [.volatileResults])`; ensure assets via `AssetInventory` (request + `downloadAndInstall` if needed, else throw `assetUnavailable`); create `SpeechAnalyzer(modules: [transcriber])`; make `AsyncStream<AnalyzerInput>` input; `analyzer.start(inputSequence:)`; spawn a results task: volatile results → partial callback, final results → accumulate.
  - `append(samples:)`: wrap in `AVAudioPCMBuffer` (convert to `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])` via `Resampler`), yield as `AnalyzerInput`.
  - `finish()`: finish input stream; `try await analyzer.finalizeAndFinishThroughEndOfInput()`; join accumulated finals.
  - Exact API names drift across seeds — adapt to what compiles against the macOS 26.0 SDK; the protocol surface is the contract.
- [ ] Step 3: Test passes. Commit `feat: Apple SpeechTranscriber engine (zero-download fallback)`.

### Task 3: EngineManager (selection + download progress, TDD for logic)

**Files:** Create `Sources/PlynnKit/EngineManager.swift`; Test `Tests/PlynnKitTests/EngineManagerTests.swift`

- [ ] Step 1: Failing tests for the pure selection logic:

```swift
func testSelection() {
    XCTAssertEqual(EngineChoice.select(preferred: .parakeet, parakeetReady: false), .apple)
    XCTAssertEqual(EngineChoice.select(preferred: .parakeet, parakeetReady: true), .parakeet)
    XCTAssertEqual(EngineChoice.select(preferred: .apple, parakeetReady: true), .apple)
}
func testParakeetReadyDetection() {
    XCTAssertFalse(EngineChoice.parakeetModelsPresent(in: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)))
}
```

- [ ] Step 2: Implement `EngineChoice` enum (`parakeet`, `apple`, `auto`) with the pure helpers (`parakeetModelsPresent` = FluidAudio cache dir `…/Application Support/FluidAudio/Models/parakeet-unified*` contains an encoder file). `@MainActor @Observable EngineManager`: holds both engines, `var active: any DictationEngine`, `var downloadProgress: Double?`; on init with `parakeetReady == false`, kicks a background `UnifiedAsrManager.loadModels(progressHandler:)` download feeding `downloadProgress`, then swaps `active` to Parakeet **only between sessions** (AppDelegate asks `engineManager.engineForNewSession()` at each `.startRecording`).
- [ ] Step 3: Tests pass; AppDelegate uses `engineManager.engineForNewSession()`. Commit `feat: engine manager with auto-fallback and background model download`.

### Task 4: Permissions model + onboarding window

**Files:** Create `Sources/PlynnKit/Permissions.swift`, `Sources/Plynn/OnboardingWindow.swift` (executable target — needs AppKit app context)

- [ ] Step 1: `Permissions` (MainActor): `static func micStatus() -> Bool` (`AVCaptureDevice.authorizationStatus(for: .audio) == .authorized`), `static func accessibilityStatus() -> Bool` (`AXIsProcessTrusted()`), `static func globeKeySafe() -> Bool` (`AppleFnUsageType` defaults == 0), `requestMic()`, `promptAccessibility()` (AXIsProcessTrustedWithOptions with prompt), `openAccessibilitySettings()` deep link, `setGlobeKeyDoNothing()` (runs `defaults write com.apple.HIToolbox AppleFnUsageType -int 0` for the user from an explicit button press).
- [ ] Step 2: `OnboardingWindow`: SwiftUI checklist — Microphone / Accessibility / Globe key rows with live status (1 s poll timer), action buttons, "Relaunch Plynn" button (`NSApplication` relaunch via `Process` + terminate) shown after accessibility grant, and a live "try it" row that says "Hold fn and speak" with engine + download status ("Using Apple engine while Parakeet downloads — 43%"). Show at launch when any permission is missing; menu item "Setup…" reopens it.
- [ ] Step 3: Build; manual verify in Task 7. Commit `feat: permissions model + onboarding checklist window`.

### Task 5: Settings window + launch at login

**Files:** Create `Sources/Plynn/SettingsWindow.swift`, `Sources/PlynnKit/Prefs.swift`

- [ ] Step 1: `Prefs` (@Observable, UserDefaults-backed): `engineChoice: EngineChoice` (auto default), `launchAtLogin: Bool` (SMAppService.mainApp register/unregister with error surfacing).
- [ ] Step 2: Settings window (SwiftUI Form): engine picker (Auto / Parakeet / Apple + current status line incl. download progress), launch-at-login toggle, "Open Setup…" button, version footer. Menu bar gains "Settings…" (Cmd-,).
- [ ] Step 3: Build. Commit `feat: settings window with engine picker and launch-at-login`.

### Task 6: First-run wiring + status menu polish

**Files:** Modify `Sources/Plynn/main.swift`

- [ ] Step 1: On launch: if `!Permissions.micStatus() || !Permissions.accessibilityStatus()` → show onboarding (activation policy `.regular` while a window is open, back to `.accessory` on close). Menu: state line shows active engine ("Parakeet (local)" / "Apple — Parakeet downloading 43%"), Settings…, Setup…, Quit.
- [ ] Step 2: `swift test` all green; `./scripts/make-app.sh`. Commit `feat: first-run onboarding flow + engine status in menu`.

### Task 7: E2E validation (Carlton)

- [ ] `tccutil reset All co.charmtechnologies.plynn.spike` (optional, to simulate fresh install) → launch → onboarding appears, statuses live-update as you grant; relaunch button works.
- [ ] Rename the FluidAudio models dir temporarily → dictation still works via Apple engine immediately; menu shows download progress; after download completes, next dictation uses Parakeet (menu reflects it).
- [ ] Settings: launch-at-login toggle survives reboot check; engine picker forces Apple/Parakeet correctly.
- [ ] Everything from the 1a checklist still passes.
