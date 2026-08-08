import XCTest
@testable import PlynnKit

final class AppleSpeechEngineTests: XCTestCase {
    func testTranscribesFixtureWithPartials() async throws {
        let engine = AppleSpeechEngine()
        do { try await engine.start() } catch AppleSpeechEngine.EngineError.assetUnavailable {
            throw XCTSkip("English speech asset unavailable on this machine")
        }
        nonisolated(unsafe) var partials: [String] = []
        await engine.setPartialCallback { partials.append($0) }
        let samples = try AudioFile.loadSamples16kMono(
            url: Bundle.module.url(forResource: "Fixtures/hello.wav", withExtension: nil)!)
        for chunk in samples.chunks(of: 8_000) {
            try await engine.append(samples: Array(chunk))
        }
        let final = try await engine.finish()
        XCTAssertTrue(final.lowercased().contains("hello"), "got: \(final)")
    }

    func testReuseAcrossSessions() async throws {
        let engine = AppleSpeechEngine()
        do { try await engine.start() } catch AppleSpeechEngine.EngineError.assetUnavailable {
            throw XCTSkip("English speech asset unavailable on this machine")
        }
        let samples = try AudioFile.loadSamples16kMono(
            url: Bundle.module.url(forResource: "Fixtures/short.wav", withExtension: nil)!)
        try await engine.append(samples: samples)
        let first = try await engine.finish()
        XCTAssertTrue(first.lowercased().contains("test"), "got: \(first)")
        try await engine.start()
        try await engine.append(samples: samples)
        let second = try await engine.finish()
        XCTAssertTrue(second.lowercased().contains("test"), "got: \(second)")
    }
}
