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

    /// Segments of a still-open utterance carry a placeholder duration (~0.01 s).
    private static let openSegmentDuration: TimeInterval = 0.05
    /// Serial, so results reach the event stream in the order they were produced.
    private static let callbackQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private struct Event: Sendable {
        var text: String?
        var segmentCount = 0
        var closed = false
        var isFinal = false
        var errorDomain: String?
        var errorCode = 0
    }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Result streams still open, by generation. A stream closes when its
    /// task delivers a final result or error.
    private var sinks: [Int: AsyncStream<Event>.Continuation] = [:]
    /// Bumped per request; results from an older request are ignored, so a
    /// cancelled session can never end or overwrite the current one.
    private var generation = 0
    private var transcript = UtteranceAccumulator()
    private var finished = false
    private var lastError: (domain: String, code: Int)?
    private var partialCallback: (@Sendable (String) -> Void)?

    public init() {}

    /// Authorize and load the recognizer ahead of the first dictation.
    public func warmUp() async {
        do { _ = try await preparedRecognizer() } catch {
            NSLog("plynn: speech warm-up failed: %@", "\(error)")
        }
    }

    public func start() async throws {
        teardown()
        generation += 1
        let gen = generation
        transcript = UtteranceAccumulator()
        finished = false
        lastError = nil

        // The on-device service fails a new request with "no speech" (1110)
        // if the previous one is still shutting down, so let it finish.
        await drainPreviousTasks()
        let recognizer = try await preparedRecognizer()
        // A newer session started (or this one was discarded) while we waited.
        guard gen == generation, !Task.isCancelled else { return }
        beginRequest(on: recognizer, generation: gen)
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
        guard let request else { throw EngineError.notStarted }
        let gen = generation
        request.endAudio()

        // The last word only arrives in the final result, so wait for it.
        var text = transcript.text
        let deadline = ContinuousClock.now + .seconds(8)
        while !finished, gen == generation, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(30))
            if gen == generation { text = transcript.text }
        }
        guard gen == generation else { return Self.trimmed(text) }
        if !finished { NSLog("plynn: speech final result timed out") }

        text = transcript.text
        let error = lastError
        teardown()
        let result = Self.trimmed(text)
        if result.isEmpty, let error {
            if Self.isAssetError(domain: error.domain, code: error.code) {
                throw EngineError.assetUnavailable
            }
        }
        return result
    }

    /// Abandon the current session without waiting for a result.
    public func cancel() {
        teardown()
    }

    private func preparedRecognizer() async throws -> SFSpeechRecognizer {
        if let recognizer, recognizer.isAvailable { return recognizer }
        let status = await Self.requestAuthorization()
        guard status == .authorized else { throw EngineError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
            recognizer.isAvailable
        else { throw EngineError.recognizerUnavailable }
        // Prefer the on-device model. If it is not installed, recognition
        // fails locally rather than uploading audio to Apple.
        if !recognizer.supportsOnDeviceRecognition {
            NSLog("plynn: on-device speech model missing — enable Dictation in System Settings")
        }
        recognizer.queue = Self.callbackQueue
        self.recognizer = recognizer
        return recognizer
    }

    private func beginRequest(on recognizer: SFSpeechRecognizer, generation gen: Int) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request

        let (events, sink) = AsyncStream.makeStream(of: Event.self)
        sinks[gen] = sink
        task = recognizer.recognitionTask(with: request) { result, error in
            var event = Event()
            if let result {
                let segments = result.bestTranscription.segments
                event.text = result.bestTranscription.formattedString
                event.segmentCount = segments.count
                event.closed = (segments.last?.duration ?? 0) > Self.openSegmentDuration
                event.isFinal = result.isFinal
            }
            if let error {
                let ns = error as NSError
                event.errorDomain = ns.domain
                event.errorCode = ns.code
            }
            sink.yield(event)
            if event.isFinal || error != nil { sink.finish() }
        }
        Task {
            for await event in events {
                self.handle(event, generation: gen)
            }
            self.sinks[gen] = nil
        }
    }

    private func drainPreviousTasks() async {
        guard !sinks.isEmpty else { return }
        let started = ContinuousClock.now
        let deadline = started + .milliseconds(1500)
        while !sinks.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if sinks.isEmpty {
            NSLog("plynn: previous speech task ended after %@", "\(started.duration(to: .now))")
        } else {
            NSLog("plynn: previous speech task did not end; starting anyway")
            for sink in sinks.values { sink.finish() }
            sinks.removeAll()
        }
    }

    private func handle(_ event: Event, generation gen: Int) {
        guard gen == generation else { return }
        if let text = event.text {
            transcript.update(
                text: text, segmentCount: event.segmentCount,
                closed: event.closed, isFinal: event.isFinal)
            partialCallback?(transcript.text)
        }
        if event.isFinal { finished = true }
        if let domain = event.errorDomain {
            lastError = (domain, event.errorCode)
            finished = true
            NSLog("plynn: speech error %@ %ld", domain, event.errorCode)
        }
    }

    private func teardown() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        finished = true
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isAssetError(domain: String, code: Int) -> Bool {
        // Speech / assistant errors when the on-device locale pack is missing.
        domain == "kAFAssistantErrorDomain" && (code == 203 || code == 1700)
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current }
        // The callback runs on a background queue; it must not be inferred
        // main-actor isolated or the runtime traps when it fires.
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }
}
