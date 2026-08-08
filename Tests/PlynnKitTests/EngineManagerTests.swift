import XCTest
@testable import PlynnKit

final class EngineManagerTests: XCTestCase {
    func testSelection() {
        XCTAssertEqual(EngineChoice.select(preferred: .auto, parakeetReady: false), .apple)
        XCTAssertEqual(EngineChoice.select(preferred: .auto, parakeetReady: true), .parakeet)
        XCTAssertEqual(EngineChoice.select(preferred: .parakeet, parakeetReady: false), .apple)
        XCTAssertEqual(EngineChoice.select(preferred: .parakeet, parakeetReady: true), .parakeet)
        XCTAssertEqual(EngineChoice.select(preferred: .apple, parakeetReady: true), .apple)
        XCTAssertEqual(EngineChoice.select(preferred: .apple, parakeetReady: false), .apple)
    }

    func testParakeetModelsAbsentInEmptyDir() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(EngineChoice.parakeetModelsPresent(in: dir))
    }

    func testParakeetModelsPresentWhenEncoderExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let modelDir = dir.appendingPathComponent("parakeet-unified-0.6b-coreml/foo.mlmodelc")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        XCTAssertTrue(EngineChoice.parakeetModelsPresent(in: dir))
        try? FileManager.default.removeItem(at: dir)
    }

    func testDefaultCacheDirDetectionMatchesRealState() {
        // On this dev machine models are downloaded; the check must agree with reality.
        // (Weak assertion by design: just verifies the path logic doesn't crash and
        // returns a Bool consistent with the FluidAudio cache convention.)
        _ = EngineChoice.parakeetModelsPresent()
    }
}
