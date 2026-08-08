import XCTest
@testable import PlynnKit

/// Heavy integration tests — first run downloads ~2.3 GB and uses the GPU.
/// Enabled only with PLYNN_LLM_TESTS=1.
final class LLMFormatterTests: XCTestCase {
    func requireEnabled() throws {
        if ProcessInfo.processInfo.environment["PLYNN_LLM_TESTS"] != "1" {
            throw XCTSkip("set PLYNN_LLM_TESTS=1 to run LLM integration tests")
        }
    }

    func testFillerAndBacktrackCleanup() async throws {
        try requireEnabled()
        let llm = LLMFormatter()
        try await llm.ensureLoaded()
        let input = "um so basically we should ship on friday actually monday"
        let out = await llm.format(input, tone: .neutral, technical: false)
        let lower = out.lowercased()
        XCTAssertFalse(lower.contains("um"), "got: \(out)")
        XCTAssertFalse(lower.contains("friday"), "backtrack not applied: \(out)")
        XCTAssertTrue(lower.contains("monday"), "got: \(out)")
    }

    func testDoesNotAnswerQuestions() async throws {
        try requireEnabled()
        let llm = LLMFormatter()
        try await llm.ensureLoaded()
        let input = "what time is the meeting tomorrow"
        let out = await llm.format(input, tone: .casual, technical: false)
        // Must clean the question, not answer it.
        XCTAssertTrue(out.lowercased().contains("meeting"), "got: \(out)")
        XCTAssertLessThan(out.count, input.count * 2, "answered instead of cleaned: \(out)")
    }

    func testNotLoadedFallsBackToInput() async {
        let llm = LLMFormatter()
        let out = await llm.format("anything at all", tone: .neutral, technical: false)
        XCTAssertEqual(out, "anything at all")
    }
}
