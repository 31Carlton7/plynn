import Foundation
import XCTest

enum TestConfiguration {
    /// Model-backed tests are opt-in so ordinary CI stays deterministic and
    /// does not download or initialize the Neural Engine model.
    static func requireModelIntegration() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLYNN_RUN_MODEL_TESTS"] == "1",
            "Model integration tests disabled; set PLYNN_RUN_MODEL_TESTS=1 to run them")
    }
}

extension Array {
    /// Split into consecutive slices of at most `size` elements — used to feed
    /// fixture audio to streaming engines the way the mic does.
    func chunks(of size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
