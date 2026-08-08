import XCTest
@testable import PlynnKit

final class StreamingTranscriberTests: XCTestCase {
    func testStreamedFixtureProducesPartialsAndFinal() async throws {
        let st = StreamingTranscriber()
        try await st.start()
        nonisolated(unsafe) var partials: [String] = []
        await st.setPartialCallback { partials.append($0) }
        let samples = try AudioFile.loadSamples16kMono(
            url: Bundle.module.url(forResource: "Fixtures/hello.wav", withExtension: nil)!)
        for chunk in samples.chunks(of: 8_000) {     // feed 0.5 s at a time
            try await st.append(samples: Array(chunk))
        }
        let final = try await st.finish()
        XCTAssertTrue(final.lowercased().contains("hello"), "got: \(final)")
        XCTAssertFalse(partials.isEmpty, "expected live partials during streaming")
    }

    func testSilenceProducesEmptyTranscript() async throws {
        let st = StreamingTranscriber()
        try await st.start()
        try await st.append(samples: [Float](repeating: 0, count: 48_000))  // 3 s silence
        let final = try await st.finish()
        XCTAssertEqual(final.trimmingCharacters(in: .whitespacesAndNewlines), "",
                       "silence must not hallucinate text; got: '\(final)'")
    }

    func testReuseAcrossSessions() async throws {
        let st = StreamingTranscriber()
        try await st.start()
        let samples = try AudioFile.loadSamples16kMono(
            url: Bundle.module.url(forResource: "Fixtures/short.wav", withExtension: nil)!)
        try await st.append(samples: samples)
        let first = try await st.finish()
        XCTAssertTrue(first.lowercased().contains("test"), "got: \(first)")
        // Second session on the same instance must not leak state.
        try await st.start()
        try await st.append(samples: samples)
        let second = try await st.finish()
        XCTAssertTrue(second.lowercased().contains("test"), "got: \(second)")
    }
}
