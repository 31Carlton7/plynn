import XCTest
@testable import PlynnKit

final class EngineManagerTests: XCTestCase {
    func testSelectionAlwaysAppleOnThisPort() {
        XCTAssertEqual(EngineChoice.select(preferred: .auto, parakeetReady: false), .apple)
        XCTAssertEqual(EngineChoice.select(preferred: .auto, parakeetReady: true), .apple)
        XCTAssertEqual(EngineChoice.select(preferred: .parakeet, parakeetReady: false), .apple)
        XCTAssertEqual(EngineChoice.select(preferred: .parakeet, parakeetReady: true), .apple)
        XCTAssertEqual(EngineChoice.select(preferred: .apple, parakeetReady: true), .apple)
        XCTAssertEqual(EngineChoice.select(preferred: .apple, parakeetReady: false), .apple)
    }

    func testParakeetModelsNeverPresentOnIntelPort() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(EngineChoice.parakeetModelsPresent(in: dir))
        XCTAssertFalse(EngineChoice.parakeetModelsPresent())
    }
}
