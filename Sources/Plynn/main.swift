import AppKit
import PlynnKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkey = HotkeyMonitor()
    let secureWatcher = SecureInputWatcher()
    let streaming = StreamingTranscriber()
    let model = IndicatorModel()
    lazy var panel = IndicatorPanel(model: model)
    var statusItem: NSStatusItem!

    var session = Session()
    var recorder: AudioRecorder?
    var chunkContinuation: AsyncStream<[Float]>.Continuation?
    var feedTask: Task<Void, Never>?
    var releasedAt: ContinuousClock.Instant?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("plynn: starting; RSS %.0f MB", Metrics.residentMB())
        setUpStatusItem()

        // Warm models so the first dictation doesn't pay the load cost.
        Task {
            try? await streaming.start()
            NSLog("plynn: models warm; RSS %.0f MB", Metrics.residentMB())
        }

        model.onTap = { [weak self] in self?.dispatch(.stopRequested) }

        hotkey.onFnDown = { [weak self] in self?.dispatch(.fnDown) }
        hotkey.onFnUp = { [weak self] in self?.dispatch(.fnUp) }
        hotkey.onKeyDown = { [weak self] keycode in
            self?.dispatch(keycode == 53 ? .escape : .otherKeyDown)
        }

        secureWatcher.onChange = { [weak self] on in
            guard let self else { return }
            dispatch(.secureInputChanged(on))
            if on {
                model.phase = .secure
                panel.show()
            } else {
                panel.hide()
            }
            refreshStatusIcon()
        }
        secureWatcher.start()

        if !hotkey.start() {
            NSLog("plynn: NO ACCESSIBILITY PERMISSION — grant in System Settings, then relaunch")
        }
    }

    func dispatch(_ event: Session.Event) {
        for effect in session.handle(event, at: .now) {
            perform(effect)
        }
        // Covers the no-effect paths back to idle (e.g. empty transcript → no paste).
        if session.state == .idle, recorder == nil, model.phase != .secure {
            panel.hide()
        }
        refreshStatusIcon()
    }

    func perform(_ effect: Session.Effect) {
        switch effect {
        case .startRecording:
            let handsFree = session.state == .recording(.handsFree)
            if handsFree { NSSound(named: "Pop")?.play() }
            model.phase = .recording(handsFree: handsFree)
            model.partial = ""
            model.level = 0
            panel.show()

            let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
            chunkContinuation = continuation
            let streaming = streaming
            feedTask = Task {
                try? await streaming.start()
                await streaming.setPartialCallback { [weak self] text in
                    Task { @MainActor in self?.model.partial = text }
                }
                for await chunk in stream {  // AsyncStream preserves chunk order
                    try? await streaming.append(samples: chunk)
                }
            }

            let r = AudioRecorder()
            recorder = r
            r.onChunk = { [weak self] chunk in
                continuation.yield(chunk)
                let level = AudioLevel.rms(of: chunk)
                Task { @MainActor in self?.model.level = level }
            }
            do { try r.start() } catch {
                NSLog("plynn: mic error \(error)")
                dispatch(.escape)  // tear the session back down
            }

        case .stopAndTranscribe:
            let samples = recorder?.stop() ?? []
            recorder = nil
            releasedAt = .now
            chunkContinuation?.finish()
            chunkContinuation = nil
            model.phase = .transcribing
            NSLog("plynn: captured %.1fs", Double(samples.count) / 16_000)
            let feedTask = feedTask
            let streaming = streaming
            Task {
                await feedTask?.value  // all chunks fed, in order
                let text = (try? await streaming.finish()) ?? ""
                await MainActor.run { self.dispatch(.transcriptReady(text)) }
            }

        case .discardRecording:
            _ = recorder?.stop()
            recorder = nil
            chunkContinuation?.finish()
            chunkContinuation = nil
            feedTask?.cancel()
            feedTask = nil
            panel.hide()

        case .cancelTranscription:
            panel.hide()

        case .paste(let text):
            if let releasedAt {
                NSLog("plynn: [%@ latency] RSS %.0f MB — %@",
                      "\(releasedAt.duration(to: .now))", Metrics.residentMB(), text)
            }
            Paster.paste(text)
            panel.hide()
        }
    }

    func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshStatusIcon()
        let menu = NSMenu()
        let state = NSMenuItem(title: "Plynn 0.1 — hold fn to dictate", action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Plynn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private var currentIconName = ""

    func refreshStatusIcon() {
        let name: String
        switch session.state {
        case .recording: name = "mic.fill"
        case .transcribing: name = "waveform"
        default: name = "mic"
        }
        guard name != currentIconName else { return }  // called on every keystroke
        currentIconName = name
        statusItem.button?.image = NSImage(
            systemSymbolName: name, accessibilityDescription: "Plynn")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
