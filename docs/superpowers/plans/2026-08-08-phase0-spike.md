# Plynn Phase 0 Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate Plynn's core thesis end-to-end: hold fn → capture mic audio at 16 kHz → transcribe locally with FluidAudio/Parakeet → paste into the frontmost app, measuring release-to-paste latency, short-utterance correctness, and RAM.

**Architecture:** A Swift Package with a library (`PlynnSpikeKit`: Transcriber, AudioRecorder, Paster, HotkeyMonitor, Metrics) and a thin executable (`PlynnSpike`) wired together by an `NSApplication` delegate, bundled into a signed `Plynn.app` by a script. TDD for the pure/audio-file paths (transcription, format conversion) with `say`-synthesized WAV fixtures; scripted manual verification for TCC-gated system pieces (mic, event tap, paste).

**Tech Stack:** Swift 6 / SPM, FluidAudio (Parakeet TDT, ANE), AVAudioEngine + AVAudioConverter, CGEventTap, NSPasteboard + CGEvent Cmd-V, XCTest.

**Deviation from PLAN.md (flagged):** Phase 0 uses `AVAudioEngine.inputNode` (the "simple path") instead of the raw AUHAL recorder. AUHAL's benefits (device pinning, mid-record switching) don't affect the spike's go/no-go metrics and it's ~5x the code. AUHAL lands in Phase 1.

**Go/no-go criteria (evaluated in Task 8):**
- Release-to-paste latency < 1.0 s for a ~10 s utterance (target ~0.5 s)
- 10/10 utterances paste non-empty, including 3 short (< 2 s) ones — no truncation/empties
- App RSS < 2 GB with models loaded
- Total energy/feel: usable as a daily driver for raw dictation

---

### Task 1: Repo + package scaffold

**Files:**
- Create: `.gitignore`, `Package.swift`
- Create: `Sources/PlynnSpikeKit/Placeholder.swift` (deleted in Task 2), `Sources/PlynnSpike/main.swift` (minimal)

- [ ] **Step 1: Verify toolchain and FluidAudio version**

Run: `swift --version && curl -s https://api.github.com/repos/FluidInference/FluidAudio/releases/latest | grep tag_name`
Expected: Swift 6.x; a tag like `"v0.9.x"`. Use the major.minor from the tag in Package.swift below (shown as `0.9.0` — substitute what the API returns).

- [ ] **Step 2: git init and .gitignore**

```bash
cd /Users/carltonaikins/Desktop/Home/Work/Projects/plynn
git init -b main
printf '.build/\nbuild/\n.DS_Store\n*.xcodeproj\n' > .gitignore
git add docs .gitignore && git commit -m "docs: Plynn plan v1.1 + phase 0 spike plan"
```

- [ ] **Step 3: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlynnSpike",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "PlynnSpikeKit",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(
            name: "PlynnSpike",
            dependencies: ["PlynnSpikeKit"]),
        .testTarget(
            name: "PlynnSpikeKitTests",
            dependencies: ["PlynnSpikeKit"],
            resources: [.copy("Fixtures")]),
    ]
)
```

- [ ] **Step 4: Minimal sources so it builds**

`Sources/PlynnSpikeKit/Placeholder.swift`:
```swift
public enum PlynnSpikeKit {}
```

`Sources/PlynnSpike/main.swift`:
```swift
print("plynn spike")
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!` (first run resolves FluidAudio; if the version tag doesn't exist, re-check Step 1 and fix).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: SPM scaffold with FluidAudio dependency"
```

---

### Task 2: Audio fixtures + WAV loading

**Files:**
- Create: `scripts/make-fixtures.sh`
- Create: `Tests/PlynnSpikeKitTests/Fixtures/` (generated)
- Create: `Sources/PlynnSpikeKit/AudioFile.swift`
- Test: `Tests/PlynnSpikeKitTests/AudioFileTests.swift`

- [ ] **Step 1: Fixture generation script**

`scripts/make-fixtures.sh`:
```bash
#!/bin/bash
set -euo pipefail
DIR="$(dirname "$0")/../Tests/PlynnSpikeKitTests/Fixtures"
mkdir -p "$DIR"
say -v Samantha --data-format=LEF32@16000 -o "$DIR/hello.wav" \
  "Hello world. This is a test of the Plynn dictation spike, recording a full sentence with punctuation."
say -v Samantha --data-format=LEF32@16000 -o "$DIR/short.wav" "Testing"
say -v Samantha --data-format=LEF32@16000 -o "$DIR/long.wav" \
  "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. \
How vexingly quick daft zebras jump. The five boxing wizards jump quickly. \
Sphinx of black quartz, judge my vow. Two driven jocks help fax my big quiz."
```

Run: `chmod +x scripts/make-fixtures.sh && ./scripts/make-fixtures.sh && afinfo Tests/PlynnSpikeKitTests/Fixtures/hello.wav | head -5`
Expected: three WAV files; afinfo shows 16000 Hz, 1 ch, Float32. (If `say` rejects `.wav`, switch the extension to `.caf` in the script and tests — `AVAudioFile` reads both.)

- [ ] **Step 2: Write the failing test**

`Tests/PlynnSpikeKitTests/AudioFileTests.swift`:
```swift
import XCTest
@testable import PlynnSpikeKit

final class AudioFileTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }

    func testLoadsFixtureAs16kMonoFloats() throws {
        let samples = try AudioFile.loadSamples16kMono(url: fixtureURL("hello.wav"))
        // ~6s sentence → between 2s and 15s of 16k samples
        XCTAssertGreaterThan(samples.count, 32_000)
        XCTAssertLessThan(samples.count, 240_000)
        XCTAssertTrue(samples.contains { abs($0) > 0.01 }, "audio should be non-silent")
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter AudioFileTests 2>&1 | tail -5`
Expected: FAIL — `AudioFile` not found (compile error counts as the failing state).

- [ ] **Step 4: Implement AudioFile**

`Sources/PlynnSpikeKit/AudioFile.swift`:
```swift
import AVFoundation

public enum AudioFile {
    public static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// Reads any audio file and returns 16 kHz mono Float32 samples.
    public static func loadSamples16kMono(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inBuf = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        return try Resampler.convert(buffer: inBuf, to: targetFormat)
    }
}
```

`Sources/PlynnSpikeKit/Resampler.swift`:
```swift
import AVFoundation

public enum Resampler {
    public static func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> [Float] {
        if buffer.format == format { return floats(from: buffer) }
        let converter = AVAudioConverter(from: buffer.format, to: format)!
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 1024)
        let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
        var fed = false
        var convError: NSError?
        converter.convert(to: outBuf, error: &convError) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        if let convError { throw convError }
        return floats(from: outBuf)
    }

    private static func floats(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
}
```

Delete `Sources/PlynnSpikeKit/Placeholder.swift`.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter AudioFileTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 6: Resampler unit test (48k → 16k)**

Append to `AudioFileTests.swift`:
```swift
    func testResamples48kStereoTo16kMono() throws {
        let inFmt = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 48_000)!
        buf.frameLength = 48_000  // 1 second, 440 Hz sine
        for ch in 0..<2 {
            let p = buf.floatChannelData![ch]
            for i in 0..<48_000 { p[i] = sinf(2 * .pi * 440 * Float(i) / 48_000) }
        }
        let out = try Resampler.convert(buffer: buf, to: AudioFile.targetFormat)
        XCTAssertTrue((15_800...16_200).contains(out.count), "got \(out.count) samples")  // ~1s at 16k
        XCTAssertGreaterThan(out.max() ?? 0, 0.5)
    }
```

Run: `swift test --filter AudioFileTests 2>&1 | tail -5`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: WAV fixture loading + 16k mono resampler (TDD)"
```

---

### Task 3: Transcriber (FluidAudio/Parakeet)

**Files:**
- Create: `Sources/PlynnSpikeKit/Transcriber.swift`
- Test: `Tests/PlynnSpikeKitTests/TranscriberTests.swift`

- [ ] **Step 1: Confirm FluidAudio's current API**

Run: `curl -s https://raw.githubusercontent.com/FluidInference/FluidAudio/main/README.md | sed -n '1,120p'`
Expected: a quickstart resembling `AsrModels.downloadAndLoad()` → `AsrManager(config:)` → `initialize(models:)` → `transcribe(samples)`. If names differ from the code below, adapt the implementation in Step 4 to the README — the `Transcriber` public surface must stay as written.

- [ ] **Step 2: Write the failing tests**

`Tests/PlynnSpikeKitTests/TranscriberTests.swift`:
```swift
import XCTest
@testable import PlynnSpikeKit

final class TranscriberTests: XCTestCase {
    static var transcriber: Transcriber!

    override class func setUp() {
        super.setUp()
        transcriber = Transcriber()
    }

    func fixture(_ name: String) throws -> [Float] {
        try AudioFile.loadSamples16kMono(
            url: Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!)
    }

    func testTranscribesSentenceFixture() async throws {
        let text = try await Self.transcriber.transcribe(samples: try fixture("hello.wav"))
        let lower = text.lowercased()
        XCTAssertTrue(lower.contains("hello"), "got: \(text)")
        XCTAssertTrue(lower.contains("dictation") || lower.contains("test"), "got: \(text)")
    }

    func testShortUtteranceIsNotEmpty() async throws {
        // The #1 reliability bug in competitor apps (VoiceInk #687/#696): short clips → empty output.
        let text = try await Self.transcriber.transcribe(samples: try fixture("short.wav"))
        XCTAssertTrue(text.lowercased().contains("test"), "got: '\(text)'")
    }

    func testLatencyBudgetOnLongUtterance() async throws {
        let samples = try fixture("long.wav")           // ~20 s of speech
        _ = try await Self.transcriber.transcribe(samples: samples)  // warm-up
        let start = ContinuousClock.now
        _ = try await Self.transcriber.transcribe(samples: samples)
        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed, .seconds(2), "Parakeet on M4 Pro should be ~100x RT; got \(elapsed)")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter TranscriberTests 2>&1 | tail -5`
Expected: FAIL — `Transcriber` not found.

- [ ] **Step 4: Implement Transcriber**

`Sources/PlynnSpikeKit/Transcriber.swift`:
```swift
import FluidAudio
import Foundation

/// Wraps FluidAudio's Parakeet ASR. First call downloads models (~0.6 GB) to
/// ~/Library/Application Support — allow time + network on first run.
public actor Transcriber {
    private var manager: AsrManager?

    public init() {}

    private func loadedManager() async throws -> AsrManager {
        if let manager { return manager }
        let models = try await AsrModels.downloadAndLoad()
        let m = AsrManager(config: .default)
        try await m.initialize(models: models)
        manager = m
        return m
    }

    /// 16 kHz mono Float32 samples in, transcript out.
    public func transcribe(samples: [Float]) async throws -> String {
        let m = try await loadedManager()
        let result = try await m.transcribe(samples, source: .microphone)
        return result.text
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter TranscriberTests 2>&1 | tail -8`
Expected: PASS (3 tests). First run is slow (model download); rerun to see true latency. If the API drifted (Step 1), fix the internals only.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: FluidAudio Parakeet transcriber with latency + short-utterance tests"
```

---

### Task 4: AudioRecorder (mic → 16 kHz mono samples)

**Files:**
- Create: `Sources/PlynnSpikeKit/AudioRecorder.swift`
- Modify: `Sources/PlynnSpike/main.swift`

Mic capture can't be unit-tested in CI; the converter it relies on is already tested (Task 2). Verification is a CLI smoke test.

- [ ] **Step 1: Implement AudioRecorder**

`Sources/PlynnSpikeKit/AudioRecorder.swift`:
```swift
import AVFoundation

/// Taps the default input device, converts to 16 kHz mono Float32.
/// start() spins up the engine; stop() tears it down and returns all samples.
public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()

    public init() {}

    public func start() throws {
        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { [weak self] buffer, _ in
            guard let self, let chunk = try? Resampler.convert(buffer: buffer, to: AudioFile.targetFormat)
            else { return }
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); defer { lock.unlock() }
        return samples
    }
}
```

- [ ] **Step 2: CLI smoke test — record 3 s and transcribe**

`Sources/PlynnSpike/main.swift`:
```swift
import Foundation
import PlynnSpikeKit

// Temporary smoke test: `swift run PlynnSpike record` — speak for 3 seconds.
if CommandLine.arguments.contains("record") {
    let recorder = AudioRecorder()
    try recorder.start()
    print("Recording 3s — speak now…")
    Thread.sleep(forTimeInterval: 3)
    let samples = recorder.stop()
    print("Captured \(samples.count) samples (\(Double(samples.count) / 16_000)s)")
    let done = DispatchSemaphore(value: 0)
    Task {
        let text = try await Transcriber().transcribe(samples: samples)
        print("Transcript: \(text)")
        done.signal()
    }
    done.wait()
} else {
    print("plynn spike")
}
```

- [ ] **Step 3: Run smoke test**

Run: `swift build && swift run PlynnSpike record` — then say "testing one two three" aloud.
Expected: sample count ≈ 48 000; transcript contains what you said. (Terminal will prompt for mic access on first run — grant it.)

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: AVAudioEngine mic recorder with CLI smoke test"
```

---

### Task 5: Paster (clipboard + synthetic Cmd-V)

**Files:**
- Create: `Sources/PlynnSpikeKit/Paster.swift`
- Modify: `Sources/PlynnSpike/main.swift`

Spike version = save/set/Cmd-V/restore. Handy's read-receipt promise pattern is Phase 1.

- [ ] **Step 1: Implement Paster**

`Sources/PlynnSpikeKit/Paster.swift`:
```swift
import AppKit
import Carbon.HIToolbox

public enum Paster {
    /// Saves the clipboard string, pastes `text` via synthetic Cmd-V, restores after 0.3 s.
    public static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        let savedChangeCount = pb.changeCount

        pb.clearContents()
        // Transient marker so clipboard managers skip the transcript.
        pb.setString(text, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        // Give the pasteboard server a beat before synthesizing Cmd-V (VoiceInk uses 0.1 s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            postCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Only restore if nobody else wrote to the clipboard meanwhile.
                if pb.changeCount == savedChangeCount + 1, let saved {
                    pb.clearContents()
                    pb.setString(saved, forType: .string)
                }
            }
        }
    }

    private static func postCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        for e in [cmdDown, vDown, vUp, cmdUp] { e?.post(tap: .cghidEventTap) }
    }
}
```

- [ ] **Step 2: Add CLI smoke command**

In `main.swift`, add before the final `else`:
```swift
} else if CommandLine.arguments.contains("paste") {
    print("Focus a text field — pasting in 3s…")
    Thread.sleep(forTimeInterval: 3)
    DispatchQueue.main.async { Paster.paste("hello from plynn") }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
```

- [ ] **Step 3: Run smoke test**

Run: `swift run PlynnSpike paste`, then click into TextEdit within 3 s.
Expected: "hello from plynn" appears; your previous clipboard is intact afterwards. If nothing pastes: grant Terminal Accessibility (System Settings → Privacy & Security → Accessibility) and retry. Note: this runs under Terminal's signature; the bundled app (Task 6) uses its own identity.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: clipboard-preserving paste via synthetic Cmd-V"
```

---

### Task 6: App bundle + signing (needed before the event tap)

**Files:**
- Create: `scripts/Info.plist`, `scripts/plynn.entitlements`, `scripts/make-app.sh`

TCC grants are keyed to signing identity + bundle ID, and Tahoe blocks synthetic events from ad-hoc-signed processes — so the fn-tap work happens inside a properly signed `.app`.

- [ ] **Step 1: Find a stable signing identity**

Run: `security find-identity -v -p codesigning`
Expected: at least one `Apple Development: …` or `Developer ID Application: …` identity. Export its name: `IDENTITY="Apple Development: …"`. **If none exists, stop and report** — ad-hoc signing will make paste/hotkeys silently fail on Tahoe; Carlton needs to log into Xcode → Settings → Accounts to create a development certificate.

- [ ] **Step 2: Info.plist and entitlements**

`scripts/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Plynn</string>
    <key>CFBundleIdentifier</key><string>co.charmtechnologies.plynn.spike</string>
    <key>CFBundleName</key><string>Plynn</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Plynn records your voice while you hold the fn key to transcribe it on-device.</string>
</dict>
</plist>
```

`scripts/plynn.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
```

- [ ] **Step 3: Bundle script**

`scripts/make-app.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${IDENTITY:?Set IDENTITY to a codesigning identity from: security find-identity -v -p codesigning}"
swift build -c release
APP="build/Plynn.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/PlynnSpike "$APP/Contents/MacOS/Plynn"
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime \
  --entitlements scripts/plynn.entitlements \
  --sign "$IDENTITY" "$APP"
echo "Built and signed $APP"
```

- [ ] **Step 4: Build, sign, launch**

Run: `chmod +x scripts/make-app.sh && IDENTITY="<from step 1>" ./scripts/make-app.sh && open build/Plynn.app && sleep 2 && pgrep -fl Plynn`
Expected: signing succeeds; process `Plynn` is running (it just prints and exits for now — pgrep may show nothing; that's fine, launch success is confirmed by no error dialog).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "build: signed app bundle with mic entitlement"
```

---

### Task 7: HotkeyMonitor + full wiring

**Files:**
- Create: `Sources/PlynnSpikeKit/HotkeyMonitor.swift`, `Sources/PlynnSpikeKit/Metrics.swift`
- Rewrite: `Sources/PlynnSpike/main.swift`

- [ ] **Step 1: Implement HotkeyMonitor**

`Sources/PlynnSpikeKit/HotkeyMonitor.swift`:
```swift
import AppKit

/// CGEventTap watcher for the fn key (flagsChanged, keycode 63, .maskSecondaryFn).
/// Hold = onFnDown/onFnUp. A non-fn key pressed while fn is held marks the hold
/// "interrupted" (user was doing fn+arrow, not dictating) and suppresses onFnUp.
public final class HotkeyMonitor {
    public var onFnDown: (() -> Void)?
    public var onFnUp: (() -> Void)?
    public var onInterrupted: (() -> Void)?

    private var tap: CFMachPort?
    private var fnIsDown = false
    private var interrupted = false

    public init() {}

    public func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)  // listen, never swallow (spike)
        }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }  // nil = missing Accessibility permission
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged && keycode == 63 {
            let down = event.flags.contains(.maskSecondaryFn)
            if down && !fnIsDown {
                fnIsDown = true; interrupted = false
                DispatchQueue.main.async { self.onFnDown?() }
            } else if !down && fnIsDown {
                fnIsDown = false
                let wasInterrupted = interrupted
                DispatchQueue.main.async {
                    wasInterrupted ? self.onInterrupted?() : self.onFnUp?()
                }
            }
        } else if type == .keyDown && fnIsDown {
            interrupted = true  // fn+something = a shortcut, not dictation
        }
    }
}
```

- [ ] **Step 2: Implement Metrics**

`Sources/PlynnSpikeKit/Metrics.swift`:
```swift
import Foundation

public enum Metrics {
    /// Resident set size in MB.
    public static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }
}
```

- [ ] **Step 3: Wire everything in main.swift (replacing smoke-test commands)**

`Sources/PlynnSpike/main.swift`:
```swift
import AppKit
import PlynnSpikeKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkey = HotkeyMonitor()
    let transcriber = Transcriber()
    var recorder: AudioRecorder?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("plynn: starting; RSS %.0f MB", Metrics.residentMB())
        // Warm the model so the first dictation isn't paying the load cost.
        Task { _ = try? await transcriber.transcribe(samples: [Float](repeating: 0, count: 16_000)) }

        hotkey.onFnDown = { [self] in
            let r = AudioRecorder()
            recorder = r
            do { try r.start(); NSLog("plynn: recording…") }
            catch { NSLog("plynn: mic error \(error)") }
        }
        hotkey.onFnUp = { [self] in
            guard let r = recorder else { return }
            recorder = nil
            let samples = r.stop()
            let released = ContinuousClock.now
            NSLog("plynn: captured %.1fs", Double(samples.count) / 16_000)
            guard samples.count > 4_000 else { return }  // <0.25s = accidental tap
            Task {
                do {
                    let text = try await transcriber.transcribe(samples: samples)
                    let latency = released.duration(to: .now)
                    await MainActor.run { Paster.paste(text) }
                    NSLog("plynn: [%@ latency] RSS %.0f MB — %@",
                          "\(latency)", Metrics.residentMB(), text)
                } catch { NSLog("plynn: transcribe error \(error)") }
            }
        }
        hotkey.onInterrupted = { [self] in
            _ = recorder?.stop(); recorder = nil
            NSLog("plynn: hold interrupted (fn+key) — discarded")
        }

        if !hotkey.start() {
            NSLog("plynn: NO ACCESSIBILITY PERMISSION — grant in System Settings, then relaunch")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: Build, run, grant permissions**

```bash
IDENTITY="<same as Task 6>" ./scripts/make-app.sh && open build/Plynn.app
```

Then: System Settings → Privacy & Security → Accessibility → enable Plynn → quit (`pkill Plynn`) and relaunch (`open build/Plynn.app`) — the tap must be recreated after the grant. Also set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing** so dictation doesn't trigger Apple's popup.

Watch logs: `log stream --predicate 'process == "Plynn"' --style compact`

- [ ] **Step 5: End-to-end smoke test**

Focus TextEdit, hold fn, say "hello world this is plynn", release.
Expected: mic prompt on first record (grant); text pastes into TextEdit within ~1 s; log line shows latency + RSS. Verify fn+arrow does NOT trigger a paste (interruption path).

- [ ] **Step 6: Run full test suite, then commit**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass.

```bash
git add -A && git commit -m "feat: fn push-to-talk wired end-to-end with latency/RSS metrics"
```

---

### Task 8: Validation & go/no-go

**Files:**
- Create: `docs/spike-results.md`

- [ ] **Step 1: Structured dictation run**

With log stream open, dictate these 10 utterances into TextEdit (mix of apps welcome — try Slack/Notes too). Record per-utterance latency and pasted text verbatim:

1. "Testing" (short)
2. "Yes" (short)
3. "Sounds good, see you at three" (short)
4. A normal sentence with a name and a number
5. A two-sentence message as you'd write in Slack
6. A ~10-second continuous thought
7. A ~20-second rambling paragraph
8. Technical jargon: "push the branch to GitHub and rebase onto main, then run swift test"
9. Speaking fast
10. Speaking quietly (whisper-ish)

- [ ] **Step 2: Write results**

`docs/spike-results.md` — table of: utterance, audio seconds, latency (release→paste), pasted correctly? (Y/N), transcript errors. Plus: RSS after 10 dictations, and subjective notes (feel, misfires, fn quirks).

- [ ] **Step 3: Evaluate go/no-go**

- Latency < 1.0 s on the 10 s utterance? (expect ~0.3–0.5 s)
- 10/10 non-empty, shorts included?
- RSS < 2 GB?

If all pass → **GO**: proceed to Phase 1 planning. If any fail → diagnose before writing more code (this is exactly what the spike is for; likely fixes: model warm-up, tap timing, VAD in Phase 1).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "docs: phase 0 spike results and go/no-go"
```
