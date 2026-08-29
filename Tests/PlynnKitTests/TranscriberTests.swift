import XCTest
@testable import PlynnKit

final class TranscriberTests: XCTestCase {
    nonisolated(unsafe) static var transcriber: Transcriber!

    override class func setUp() {
        super.setUp()
        transcriber = Transcriber()
    }

    func fixture(_ name: String) throws -> [Float] {
        try AudioFile.loadSamples16kMono(
            url: Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!)
    }

    func startOrSkip() async throws {
        do {
            _ = try await Self.transcriber.transcribe(samples: [Float](repeating: 0, count: 1_600))
        } catch AppleSpeechEngine.EngineError.assetUnavailable {
            throw XCTSkip("English on-device speech asset unavailable on this machine")
        } catch AppleSpeechEngine.EngineError.notAuthorized {
            throw XCTSkip("Speech recognition not authorized in this test environment")
        } catch AppleSpeechEngine.EngineError.recognizerUnavailable {
            throw XCTSkip("Speech recognizer unavailable")
        }
    }

    func testTranscribesSentenceFixture() async throws {
        try await startOrSkip()
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
        throw XCTSkip("ANE latency budget is Parakeet-specific; Apple Speech on Intel is not realtime")
    }
}
