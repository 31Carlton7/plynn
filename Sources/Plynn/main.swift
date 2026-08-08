import AppKit
import PlynnKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkey = HotkeyMonitor()
    let transcriber = Transcriber()
    var recorder: AudioRecorder?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("plynn: starting; RSS %.0f MB", Metrics.residentMB())
        // Warm the model so the first dictation isn't paying the load cost.
        Task {
            _ = try? await transcriber.transcribe(samples: [Float](repeating: 0, count: 16_000))
            NSLog("plynn: model warm; RSS %.0f MB", Metrics.residentMB())
        }

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
