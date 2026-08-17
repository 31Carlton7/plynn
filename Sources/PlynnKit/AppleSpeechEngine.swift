import AVFoundation
import Speech

/// Zero-download dictation engine backed by macOS 26's SpeechAnalyzer /
/// SpeechTranscriber. Model assets are OS-managed; quality is Whisper-small
/// class — used while Parakeet downloads, or when the user prefers it.
public actor AppleSpeechEngine: DictationEngine {
    public enum EngineError: Error { case assetUnavailable, notStarted }

    public nonisolated let displayName = "Apple (built-in)"

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var finalText = ""
    private var partialCallback: (@Sendable (String) -> Void)?

    public init() {}

    public func start() async throws {
        // Tear down any previous session.
        inputBuilder?.finish()
        resultsTask?.cancel()
        finalText = ""

        let locale = Locale(identifier: "en_US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [])
        self.transcriber = transcriber

        // Ensure the OS speech asset for this locale is installed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            do { try await request.downloadAndInstall() } catch { throw EngineError.assetUnavailable }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputBuilder = continuation
        try await analyzer.start(inputSequence: stream)

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        await self?.appendFinal(text)
                    } else {
                        await self?.emitPartial(text)
                    }
                }
            } catch {}
        }
    }

    public func setPartialCallback(_ callback: @escaping @Sendable (String) -> Void) {
        partialCallback = callback
    }

    public func append(samples: [Float]) async throws {
        guard let inputBuilder, let analyzerFormat else { throw EngineError.notStarted }
        let src = AVAudioPCMBuffer(
            pcmFormat: AudioFile.targetFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        src.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { p in
            src.floatChannelData![0].update(from: p.baseAddress!, count: samples.count)
        }
        let converted: AVAudioPCMBuffer
        if analyzerFormat == AudioFile.targetFormat {
            converted = src
        } else {
            let out = AVAudioPCMBuffer(
                pcmFormat: analyzerFormat,
                frameCapacity: AVAudioFrameCount(
                    Double(samples.count) * analyzerFormat.sampleRate / 16_000 + 1_024))!
            let conv = AVAudioConverter(from: AudioFile.targetFormat, to: analyzerFormat)!
            var fed = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .endOfStream; return nil }
                fed = true; status.pointee = .haveData; return src
            }
            if let err { throw err }
            converted = out
        }
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }

    public func finish() async throws -> String {
        inputBuilder?.finish()
        inputBuilder = nil
        // Runs even when finalize throws — otherwise a failed session leaves a
        // live analyzer and results loop behind for the next start() to fight.
        defer {
            resultsTask?.cancel()
            resultsTask = nil
            analyzer = nil
            transcriber = nil
        }
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        return finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendFinal(_ text: String) {
        finalText += text
    }

    private func emitPartial(_ text: String) {
        partialCallback?(finalText + text)
    }
}
