import XCTest
@testable import PlynnSpikeKit

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
