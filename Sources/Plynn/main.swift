import AppKit
import PlynnKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkey = HotkeyMonitor(trigger: AppDelegate.storedHotkeyTrigger())

    static func storedHotkeyTrigger() -> HotkeyTrigger {
        UserDefaults.standard.string(forKey: "hotkeyTrigger").flatMap(HotkeyTrigger.init) ?? .fn
    }
    let secureWatcher = SecureInputWatcher()
    let engineManager = EngineManager()
    let model = IndicatorModel()
    lazy var panel = IndicatorPanel(model: model)
    lazy var onboarding = OnboardingWindowController(engineManager: engineManager)
    lazy var mainWindow = MainWindowController(engineManager: engineManager, store: store) {
        [weak self] in
        self?.onboarding.show()
    }
    var statusItem: NSStatusItem!
    let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    let store = try? PersonalStore(path: PersonalStore.defaultPath())
    lazy var formatter = TranscriptFormatter(personalization: { [store] in
        ((try? store?.snippets()) ?? [], (try? store?.terms()) ?? [])
    })
    var pendingPressEnter = false
    var lastCaptureSeconds = 0.0
    /// Non-nil when the session began with text selected → command mode.
    var pendingSelection: String?

    // Meeting mode
    var meetingRecorder: MeetingRecorder?
    var meetingEngine: (any DictationEngine)?
    var meetingContinuation: AsyncStream<[Float]>.Continuation?
    var meetingFeedTask: Task<Void, Never>?
    var meetingTranscript = MeetingTranscript()
    var meetingID: Int64?
    var meetingTimer: Timer?

    var session = Session()
    var recorder: AudioRecorder?
    /// Engine chosen at session start; never swapped mid-session.
    var sessionEngine: (any DictationEngine)?
    var chunkContinuation: AsyncStream<[Float]>.Continuation?
    var feedTask: Task<Void, Never>?
    var releasedAt: ContinuousClock.Instant?
    /// Safety net for `.transcribing`: the only ways out of that state are a
    /// transcript or an escape, so anything that hangs downstream (engine,
    /// polish model, paste) would otherwise wedge the app permanently —
    /// every later fn press falls through `Session.handle`'s `default`.
    var transcribeWatchdog: Task<Void, Never>?
    /// Generous: polish alone is allowed 10 s. This is a last resort, not a
    /// latency budget.
    static let transcribeDeadline: Duration = .seconds(25)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("plynn: starting; RSS %.0f MB; AX trusted: %d",
              Metrics.residentMB(), AXIsProcessTrusted() ? 1 : 0)
        setUpStatusItem()

        if !Permissions.micGranted() || !Permissions.accessibilityGranted() {
            onboarding.show()
        }

        // Picking a different activation key in Settings takes effect
        // immediately — no relaunch, since the tap just matches a new keycode.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let stored = AppDelegate.storedHotkeyTrigger()
                if self.hotkey.trigger != stored { self.hotkey.trigger = stored }
            }
        }

        // Warm the active engine, then the polish LLM (serialized — don't
        // compete for download bandwidth or memory pressure at launch).
        Task { [engineManager, formatter] in
            try? await engineManager.engineForNewSession().start()
            NSLog("plynn: engine warm; RSS %.0f MB", Metrics.residentMB())
            await formatter.warmLLM()
            NSLog("plynn: polish engine %@; RSS %.0f MB",
                  await formatter.polishEngine ?? "none (rules only)", Metrics.residentMB())
            if let reason = await formatter.appleFMStatus {
                NSLog("plynn: Apple Intelligence %@", reason)
            }
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
        let effects = session.handle(event, at: .now)
        for effect in effects {
            perform(effect)
        }
        if session.state != .transcribing {
            transcribeWatchdog?.cancel()
            transcribeWatchdog = nil
        }
        // Covers the no-effect paths back to idle (e.g. empty transcript → no
        // paste). The .done check state hides itself on a timer instead.
        if session.state == .idle, recorder == nil,
            model.phase != .secure, model.phase != .done, model.phase != .micUnavailable,
            model.phase != .meetingSaved {
            panel.hide()
        }
        refreshStatusIcon()
    }

    func perform(_ effect: Session.Effect) {
        switch effect {
        case .startRecording:
            let handsFree = session.state == .recording(.handsFree)
            // Fire before the mic opens below, so the cue doesn't bleed into
            // the first samples and get transcribed as noise.
            Feedback.play(handsFree ? .lock : .start)
            model.phase = .recording(handsFree: handsFree)
            model.partial = ""
            model.resetLevels()
            panel.show()

            pendingSelection = SelectionReader.selectedText()

            let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
            chunkContinuation = continuation
            let engine = engineManager.engineForNewSession()
            sessionEngine = engine
            feedTask = Task {
                try? await engine.start()
                await engine.setPartialCallback { [weak self] text in
                    Task { @MainActor in self?.model.partial = text }
                }
                for await chunk in stream {  // AsyncStream preserves chunk order
                    try? await engine.append(samples: chunk)
                }
            }

            let r = AudioRecorder()
            recorder = r
            r.onChunk = { [weak self] chunk in
                continuation.yield(chunk)
                // ~21 ms windows at 16 kHz: several envelope points per audio
                // callback, so the wave moves at UI rate, not buffer rate.
                let points = AudioLevel.envelope(of: chunk, windowSize: 336)
                    .map(AudioLevel.normalized)
                Task { @MainActor in self?.model.push(levels: points) }
            }
            do {
                try r.start()
            } catch {
                // A reconfiguring device (FaceTime/Zoom grabbing the mic) can
                // fail the first open; one retry after a beat usually catches
                // the settled format.
                NSLog("plynn: mic error \(error) — retrying")
                usleep(250_000)
                do {
                    try r.start()
                } catch {
                    NSLog("plynn: mic unavailable \(error)")
                    Feedback.play(.failure)
                    model.phase = .micUnavailable
                    recorder = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                        guard let self, self.model.phase == .micUnavailable else { return }
                        self.panel.hide()
                    }
                    dispatch(.escape)  // tear the session back down
                }
            }

        case .stopAndTranscribe:
            let samples = recorder?.stop() ?? []
            recorder = nil
            releasedAt = .now
            chunkContinuation?.finish()
            chunkContinuation = nil
            model.phase = .transcribing
            Feedback.play(.stop)
            startTranscribeWatchdog()
            lastCaptureSeconds = Double(samples.count) / 16_000
            NSLog("plynn: captured %.1fs", lastCaptureSeconds)
            let feedTask = feedTask
            let engine = sessionEngine
            let formatter = formatter
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let aiPolish = UserDefaults.standard.object(forKey: "aiPolish") as? Bool ?? true
            let selection = pendingSelection
            pendingSelection = nil
            Task {
                await feedTask?.value  // all chunks fed, in order
                let raw = (try? await engine?.finish()) ?? ""

                // Command mode: selection + spoken instruction → replace it.
                if let selection, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
                    let transformed = await formatter.transform(
                        selection: selection, instruction: raw)
                    await MainActor.run {
                        self.pendingPressEnter = false
                        if let transformed {
                            try? self.store?.record(
                                app: bundleID ?? "unknown", verbatim: raw,
                                formatted: transformed,
                                durationSeconds: self.lastCaptureSeconds, engine: "command")
                            // Cmd-V replaces the still-active selection.
                            self.dispatch(.transcriptReady(transformed))
                        } else {
                            NSLog("plynn: command transform failed — selection untouched")
                            Feedback.play(.failure)
                            self.dispatch(.transcriptReady(""))
                        }
                    }
                    return
                }

                let result = await formatter.format(raw, bundleID: bundleID, aiPolish: aiPolish)
                await MainActor.run {
                    self.pendingPressEnter = result.pressEnter
                    if result.text != result.verbatim {
                        NSLog("plynn: verbatim — %@", result.verbatim)
                    }
                    if !result.text.isEmpty {
                        try? self.store?.record(
                            app: bundleID ?? "unknown",
                            verbatim: result.verbatim, formatted: result.text,
                            durationSeconds: self.lastCaptureSeconds,
                            engine: engine?.displayName ?? "unknown")
                    }
                    self.dispatch(.transcriptReady(result.text))
                }
            }

        case .discardRecording:
            pendingSelection = nil
            let discarded = recorder?.stop() ?? []
            // Stay silent for the sub-minHold taps that also discard — including
            // the first half of a hands-free double-tap, where a cancel cue
            // immediately before the lock cue would just sound like a stutter.
            if Double(discarded.count) / 16_000 > 0.35 { Feedback.play(.cancel) }
            recorder = nil
            chunkContinuation?.finish()
            chunkContinuation = nil
            feedTask?.cancel()
            feedTask = nil
            panel.hide()

        case .cancelTranscription:
            panel.hide()

        case .startMeeting:
            startMeeting()

        case .stopMeeting:
            stopMeeting()

        case .paste(let text):
            if let releasedAt {
                NSLog("plynn: [%@ latency] RSS %.0f MB — %@",
                      "\(releasedAt.duration(to: .now))", Metrics.residentMB(), text)
            }
            Paster.paste(text)
            if pendingPressEnter {
                pendingPressEnter = false
                // After the paste chord (0.1 s delay + keystrokes) has landed.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { Paster.pressReturn() }
            }
            Feedback.play(.success)
            model.phase = .done
            // Shrink (0.38 s spring) + delayed check draw (0.3 + 0.28 s) + hold.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self, self.model.phase == .done else { return }
                self.panel.hide()
            }
            scheduleCorrectionCheck(pasted: text)
        }
    }

    // MARK: Meeting mode

    func startMeeting() {
        Feedback.play(.lock)
        model.resetLevels()
        model.phase = .meeting(elapsed: 0)
        panel.show()
        meetingTranscript = MeetingTranscript()

        let started = Date()
        let title = Self.defaultMeetingTitle(started)
        meetingID = try? store?.addMeeting(title: title, startedAt: started)

        // Meetings always run on Parakeet: it streams and has no session cap.
        let engine = engineManager.engineForNewSession()
        meetingEngine = engine
        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
        meetingContinuation = continuation
        meetingFeedTask = Task {
            try? await engine.start()
            await engine.setPartialCallback { [weak self] text in
                Task { @MainActor in self?.meetingPartial(text) }
            }
            for await chunk in stream {
                try? await engine.append(samples: chunk)
            }
        }

        let recorder = MeetingRecorder()
        meetingRecorder = recorder
        recorder.onChunk = { [weak self] chunk in
            continuation.yield(chunk)
            let points = AudioLevel.envelope(of: chunk, windowSize: 1_600).map(AudioLevel.normalized)
            Task { @MainActor in self?.model.push(levels: points) }
        }
        recorder.onFailure = { [weak self] error in
            NSLog("plynn: meeting stream failed: \(error)")
            Task { @MainActor in self?.dispatch(.stopRequested) }
        }
        Task {
            do {
                try await recorder.start()
            } catch {
                NSLog("plynn: meeting could not start: \(error)")
                await MainActor.run {
                    self.model.phase = .micUnavailable
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                        guard let self, self.model.phase == .micUnavailable else { return }
                        self.panel.hide()
                    }
                    self.tearDownMeeting(save: false)
                    self.dispatch(.stopRequested)
                }
            }
        }

        meetingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .meeting = self.model.phase else { return }
                self.model.phase = .meeting(elapsed: Int(self.meetingRecorder?.elapsed ?? 0))
            }
        }
    }

    /// Streaming partial: keep the latest text as the running tail; commit a
    /// segment whenever the engine's partial resets (i.e. it finalized).
    private var meetingLastPartial = ""
    private var meetingSegmentStart: TimeInterval = 0
    func meetingPartial(_ text: String) {
        let elapsed = meetingRecorder?.elapsed ?? 0
        // Parakeet's partial grows monotonically within an utterance and
        // shrinks when a new one starts — the shrink is our segment boundary.
        if text.count < meetingLastPartial.count, !meetingLastPartial.isEmpty {
            meetingTranscript.append(meetingLastPartial, at: meetingSegmentStart)
            meetingSegmentStart = elapsed
        } else if meetingLastPartial.isEmpty {
            meetingSegmentStart = elapsed
        }
        meetingLastPartial = text
    }

    func stopMeeting() {
        guard meetingRecorder != nil else { return }
        Feedback.play(.success)
        model.phase = .meetingSaved
        let recorder = meetingRecorder
        let engine = meetingEngine
        let feed = meetingFeedTask
        meetingContinuation?.finish()
        meetingTimer?.invalidate()
        meetingTimer = nil
        let elapsed = recorder?.elapsed ?? 0
        let id = meetingID
        let started = recorder?.startedAt ?? Date()
        let title = Self.defaultMeetingTitle(started)

        Task {
            await recorder?.stop()
            await feed?.value
            let final = (try? await engine?.finish()) ?? ""
            await MainActor.run {
                // Whatever the engine flushed at the end is the last segment.
                let tail = final.isEmpty ? self.meetingLastPartial : final
                if !tail.isEmpty {
                    self.meetingTranscript.append(tail, at: self.meetingSegmentStart)
                }
                self.meetingLastPartial = ""
                self.tearDownMeeting(save: false)
            }
            let transcript = await MainActor.run { self.meetingTranscript }
            guard let id, let store = self.store else { return }
            try? store.updateMeeting(
                id: id, transcript: transcript.plainText,
                durationSeconds: elapsed, status: .summarizing)

            // Summarize in the background; the pill has already moved on.
            let formatter = self.formatter
            let notes = await MeetingSummarizer.summarize(
                transcript, title: title,
                complete: { await formatter.complete($0) })
            let body = notes ?? MeetingSummarizer.pendingNote(
                title: title, transcriptWords: transcript.wordCount)
            try? store.updateMeeting(id: id, notes: body, status: notes == nil ? .failed : .ready)
            try? store.writeMarkdownFile(
                title: title, startedAt: started, notes: body,
                transcript: transcript.plainText)
            NSLog("plynn: meeting %lld saved (%@)", id, notes == nil ? "summary pending" : "notes ready")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.model.phase == .meetingSaved else { return }
            self.panel.hide()
        }
    }

    private func tearDownMeeting(save: Bool) {
        meetingRecorder = nil
        meetingEngine = nil
        meetingContinuation = nil
        meetingFeedTask = nil
        meetingTimer?.invalidate()
        meetingTimer = nil
        meetingID = save ? meetingID : nil
    }

    static func defaultMeetingTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE h:mm a"
        return "Meeting, \(f.string(from: date))"
    }

    /// A few seconds after a paste, re-read the focused field and learn
    /// dictionary aliases from any single-word ASR fixes the user made.
    func scheduleCorrectionCheck(pasted: String) {
        let learnOn = UserDefaults.standard.object(forKey: "learnCorrections") as? Bool ?? true
        guard learnOn, let store, !pasted.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.recorder == nil else { return }  // not mid-dictation
            guard let current = FieldReader.focusedFieldValue(), current != pasted else { return }
            // Only compare like-for-like: a cleared field (message sent) or a
            // long document around the paste would produce junk diffs.
            let pastedWords = pasted.split(whereSeparator: \.isWhitespace).count
            let currentWords = current.split(whereSeparator: \.isWhitespace).count
            guard abs(pastedWords - currentWords) <= 3 else { return }
            let learned = CorrectionLearner.corrections(original: pasted, edited: current)
            guard !learned.isEmpty, learned.count <= 3 else { return }
            for fix in learned {
                let terms = (try? store.terms()) ?? []
                if let existing = terms.first(where: {
                    $0.text.caseInsensitiveCompare(fix.corrected) == .orderedSame
                }) {
                    try? store.addAlias(termID: existing.id, alias: fix.heard.lowercased())
                } else {
                    try? store.addTerm(
                        text: fix.corrected, aliases: [fix.heard.lowercased()])
                }
                NSLog("plynn: learned \"%@\" → \"%@\"", fix.heard, fix.corrected)
            }
        }
    }

    var engineStateItem: NSMenuItem!
    var meetingItem: NSMenuItem!

    func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshStatusIcon()
        let menu = NSMenu()
        menu.delegate = self
        engineStateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        engineStateItem.isEnabled = false
        menu.addItem(engineStateItem)
        menu.addItem(.separator())
        let openItem = NSMenuItem(
            title: "Open Plynn", action: #selector(openHome), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let setupItem = NSMenuItem(title: "Setup…", action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        meetingItem = NSMenuItem(
            title: "Start Meeting Notes", action: #selector(toggleMeeting), keyEquivalent: "m")
        meetingItem.target = self
        menu.addItem(meetingItem)
        menu.addItem(.separator())
        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: "")
        updateItem.target = updater
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Plynn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    /// Drag the session back to `.idle` if a transcript never arrives, so one
    /// bad dictation costs a dictation rather than the rest of the session.
    /// Routed through the normal transitions (`.transcribing` → `.cancelled`
    /// → `.idle`) so no state is reachable here that `Session` can't express.
    func startTranscribeWatchdog() {
        transcribeWatchdog?.cancel()
        transcribeWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.transcribeDeadline)
            guard !Task.isCancelled, let self, self.session.state == .transcribing
            else { return }
            NSLog("plynn: transcription stalled past %@ — resetting session",
                  "\(Self.transcribeDeadline)")
            Feedback.play(.failure)
            dispatch(.escape)  // .transcribing → .cancelled
            dispatch(.transcriptReady(""))  // .cancelled → .idle
            panel.hide()
        }
    }

    @objc func openHome() { mainWindow.show(tab: .home) }
    @objc func toggleMeeting() {
        if session.state == .meeting {
            dispatch(.stopRequested)
        } else if session.state == .idle {
            // Drive the state machine the same way triple-tap does, so the
            // menu can never desync from the keyboard path.
            let now = ContinuousClock.now
            _ = session.handle(.fnDown, at: now)
            _ = session.handle(.fnUp, at: now.advanced(by: .milliseconds(50)))
            _ = session.handle(.fnDown, at: now.advanced(by: .milliseconds(100)))
            _ = session.handle(.fnUp, at: now.advanced(by: .milliseconds(150)))
            for effect in session.handle(.fnDown, at: now.advanced(by: .milliseconds(200))) {
                perform(effect)
            }
            refreshStatusIcon()
        }
    }
    @objc func openSettings() { mainWindow.show(tab: .settings) }
    @objc func openSetup() { onboarding.show() }

    /// Menu-bar app with no Dock icon: clicking Plynn.app in Finder/Launchpad
    /// re-opens it — surface the Home window so the click visibly does something.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        if !hasVisibleWindows { mainWindow.show(tab: .home) }
        return true
    }

    /// plynn://home | plynn://settings | plynn://dictionary | plynn://snippets | plynn://setup
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            case "settings": mainWindow.show(tab: .settings)
            case "notes", "meetings": mainWindow.show(tab: .notes)
            case "dictionary": mainWindow.show(tab: .dictionary)
            case "snippets": mainWindow.show(tab: .snippets)
            case "setup": onboarding.show()
            default: mainWindow.show(tab: .home)  // home, history, anything else
            }
        }
    }

    private var currentIconName = ""

    func refreshStatusIcon() {
        let name: String
        switch session.state {
        case .recording: name = "mic.fill"
        case .meeting: name = "record.circle"
        case .transcribing: name = "waveform"
        default: name = "mic"
        }
        guard name != currentIconName else { return }  // called on every keystroke
        currentIconName = name
        statusItem.button?.image = NSImage(
            systemSymbolName: name, accessibilityDescription: "Plynn")
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        engineStateItem.title = engineManager.statusLine
        meetingItem.title = session.state == .meeting ? "Stop Meeting Notes" : "Start Meeting Notes"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
