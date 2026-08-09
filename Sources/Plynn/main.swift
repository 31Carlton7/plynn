import AppKit
import PlynnKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkey = HotkeyMonitor()
    let secureWatcher = SecureInputWatcher()
    let engineManager = EngineManager()
    let model = IndicatorModel()
    lazy var panel = IndicatorPanel(model: model)
    lazy var onboarding = OnboardingWindowController(engineManager: engineManager)
    lazy var settings = SettingsWindowController(engineManager: engineManager, store: store) {
        [weak self] in
        self?.onboarding.show()
    }
    var statusItem: NSStatusItem!
    let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    let store = try? PersonalStore(path: PersonalStore.defaultPath())
    lazy var history = store.map { HistoryWindowController(store: $0) }
    lazy var formatter = TranscriptFormatter(personalization: { [store] in
        ((try? store?.snippets()) ?? [], (try? store?.terms()) ?? [])
    })
    var pendingPressEnter = false
    var lastCaptureSeconds = 0.0
    /// Non-nil when the session began with text selected → command mode.
    var pendingSelection: String?

    var session = Session()
    var recorder: AudioRecorder?
    /// Engine chosen at session start; never swapped mid-session.
    var sessionEngine: (any DictationEngine)?
    var chunkContinuation: AsyncStream<[Float]>.Continuation?
    var feedTask: Task<Void, Never>?
    var releasedAt: ContinuousClock.Instant?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("plynn: starting; RSS %.0f MB; AX trusted: %d",
              Metrics.residentMB(), AXIsProcessTrusted() ? 1 : 0)
        setUpStatusItem()

        if !Permissions.micGranted() || !Permissions.accessibilityGranted() {
            onboarding.show()
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
        for effect in session.handle(event, at: .now) {
            perform(effect)
        }
        // Covers the no-effect paths back to idle (e.g. empty transcript → no
        // paste). The .done check state hides itself on a timer instead.
        if session.state == .idle, recorder == nil,
            model.phase != .secure, model.phase != .done {
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
                let level = AudioLevel.rms(of: chunk)
                Task { @MainActor in
                    guard let self else { return }
                    // Fast attack, slow release — keeps the ribbon fluid between chunks.
                    self.model.level = max(level, self.model.level * 0.82)
                }
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
            Paster.paste(text)  // fires immediately — the check animates while it lands
            if pendingPressEnter {
                pendingPressEnter = false
                // After the paste chord (0.1 s delay + keystrokes) has landed.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { Paster.pressReturn() }
            }
            model.phase = .done
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                guard let self, self.model.phase == .done else { return }
                self.panel.hide()
            }
            scheduleCorrectionCheck(pasted: text)
        }
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

    func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshStatusIcon()
        let menu = NSMenu()
        menu.delegate = self
        engineStateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        engineStateItem.isEnabled = false
        menu.addItem(engineStateItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let historyItem = NSMenuItem(
            title: "History…", action: #selector(openHistory), keyEquivalent: "y")
        historyItem.target = self
        menu.addItem(historyItem)
        let setupItem = NSMenuItem(title: "Setup…", action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
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

    @objc func openSettings() { settings.show() }
    @objc func openSetup() { onboarding.show() }
    @objc func openHistory() { history?.show() }

    /// Menu-bar app with no Dock icon: clicking Plynn.app in Finder/Launchpad
    /// re-opens it — surface Settings so the click visibly does something.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        if !hasVisibleWindows { settings.show() }
        return true
    }

    /// plynn://settings | plynn://history | plynn://dictionary | plynn://setup
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            case "history": history?.show()
            case "setup": onboarding.show()
            default: settings.show()  // settings, dictionary, anything else
            }
        }
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

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        engineStateItem.title = engineManager.statusLine
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
