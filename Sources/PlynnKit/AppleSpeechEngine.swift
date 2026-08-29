@preconcurrency import AVFoundation
@preconcurrency import Speech

/// On-device dictation via `SFSpeechRecognizer` (macOS 15 / Sequoia).
///
/// The upstream Plynn engine is SpeechAnalyzer / SpeechTranscriber (macOS 26).
/// Those types do not exist in the Sequoia SDK, so this port uses the Speech
/// framework that ships with the OS. `requiresOnDeviceRecognition` stays on
/// so audio never leaves the Mac.
public actor AppleSpeechEngine: DictationEngine {
    public enum EngineError: Error {
        case assetUnavailable, notStarted, notAuthorized, recognizerUnavailable
    }

    public nonisolated let displayName = "Apple (built-in)"

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var accumulated = ""
    private var latestHypothesis = ""
    private var finished = false
    private var lastError: Error?
    private var partialCallback: (@Sendable (String) -> Void)?

    public init() {}

    public func start() async throws {
        await teardown()
        accumulated = ""
        latestHypothesis = ""
        finished = false
        lastError = nil

        let status = await Self.requestAuthorization()
        guard status == .authorized else { throw EngineError.notAuthorized }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
        guard let recognizer, recognizer.isAvailable else {
            throw EngineError.recognizerUnavailable
        }
        // Prefer the on-device model. If it is not installed, recognition
        // fails locally rather than uploading audio to Apple.
        if !recognizer.supportsOnDeviceRecognition {
            NSLog("plynn: on-device speech model missing — enable Dictation in System Settings")
        }
        self.recognizer = recognizer
        try beginRequest()
    }

    public func setPartialCallback(_ callback: @escaping @Sendable (String) -> Void) {
        partialCallback = callback
    }

    public func append(samples: [Float]) async throws {
        guard let request else { throw EngineError.notStarted }
        let buffer = AVAudioPCMBuffer(
            pcmFormat: AudioFile.targetFormat,
            frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: samples.count)
        }
        request.append(buffer)
    }

    public func finish() async throws -> String {
        guard request != nil else { throw EngineError.notStarted }
        request?.endAudio()

        let deadline = ContinuousClock.now + .seconds(12)
        while !finished, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(40))
        }
        let text = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = lastError
        await teardown()
        if text.isEmpty, let error, Self.isAssetError(error) {
            throw EngineError.assetUnavailable
        }
        return text
    }

    private var displayText: String {
        let hypothesis = latestHypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        if accumulated.isEmpty { return hypothesis }
        if hypothesis.isEmpty { return accumulated }
        return accumulated + " " + hypothesis
    }

    private func beginRequest() throws {
        guard let recognizer else { throw EngineError.notStarted }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request
        finished = false
        latestHypothesis = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error as NSError?
            guard let engine = self else { return }
            Task { await engine.handle(text: text, isFinal: isFinal, error: nsError) }
        }
    }

    private func handle(text: String?, isFinal: Bool, error: NSError?) {
        if let text {
            latestHypothesis = text
            if isFinal {
                if !accumulated.isEmpty, !latestHypothesis.isEmpty {
                    accumulated += " " + latestHypothesis
                } else if accumulated.isEmpty {
                    accumulated = latestHypothesis
                }
                latestHypothesis = ""
                finished = true
            }
            partialCallback?(displayText)
        }
        if let error {
            lastError = error
            finished = true
        }
    }

    private func teardown() async {
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        finished = true
    }

    private static func isAssetError(_ error: Error) -> Bool {
        let ns = error as NSError
        // Speech / assistant errors when the on-device locale pack is missing.
        return ns.domain == "kAFAssistantErrorDomain" || ns.code == 203 || ns.code == 1700
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let current = SFSpeechRecognizer.authorizationStatus()
                if current != .notDetermined {
                    continuation.resume(returning: current)
                    return
                }
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }
}
