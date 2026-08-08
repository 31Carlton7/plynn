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
} else if CommandLine.arguments.contains("paste") {
    print("Focus a text field — pasting in 3s…")
    Thread.sleep(forTimeInterval: 3)
    DispatchQueue.main.async { Paster.paste("hello from plynn") }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
} else {
    print("plynn spike")
}
