import Foundation
import XCTest
@testable import PlynnKit

/// Deterministic engine seam for CI. It models cold start, warm start, and
/// finalization without downloading or executing a speech model.
actor MockDictationEngine: DictationEngine {
    enum MockError: Error {
        case notStarted
    }

    nonisolated let displayName = "Mock"

    private let coldStartDelay: Duration
    private let warmStartDelay: Duration
    private let finishDelay: Duration
    private let output: String
    private let ignoresCancellation: Bool
    private var started = false
    private(set) var startCount = 0
    private(set) var appendCount = 0
    private(set) var finishCount = 0

    init(
        output: String = "hello from mock",
        coldStartDelay: Duration = .zero,
        warmStartDelay: Duration = .zero,
        finishDelay: Duration = .zero,
        ignoresCancellation: Bool = false
    ) {
        self.output = output
        self.coldStartDelay = coldStartDelay
        self.warmStartDelay = warmStartDelay
        self.finishDelay = finishDelay
        self.ignoresCancellation = ignoresCancellation
    }

    func start() async throws {
        startCount += 1
        if ignoresCancellation {
            await withUnsafeContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    continuation.resume()
                }
            }
        } else {
            try await wait(startCount == 1 ? coldStartDelay : warmStartDelay)
        }
        started = true
    }

    func setPartialCallback(_ callback: @escaping @Sendable (String) -> Void) async {}

    func append(samples: [Float]) async throws {
        guard started else { throw MockError.notStarted }
        appendCount += 1
    }

    func finish() async throws -> String {
        guard started else { throw MockError.notStarted }
        try await wait(finishDelay)
        finishCount += 1
        started = false
        return output
    }

    private func wait(_ delay: Duration) async throws {
        guard delay > .zero else { return }
        try await Task.sleep(for: delay)
    }
}

actor MockPasteSink {
    private(set) var text: String?

    func paste(_ value: String) {
        text = value
    }
}

final class LatencyTests: XCTestCase {
    func testColdAndWarmEngineStartLatency() async throws {
        let engine = MockDictationEngine(
            coldStartDelay: .milliseconds(40), warmStartDelay: .milliseconds(1))

        let coldStart = ContinuousClock.now
        try await engine.start()
        let cold = coldStart.duration(to: .now)

        let warmStart = ContinuousClock.now
        try await engine.start()
        let warm = warmStart.duration(to: .now)

        let startCount = await engine.startCount
        XCTAssertEqual(startCount, 2)
        XCTAssertGreaterThan(cold, .milliseconds(15))
        XCTAssertLessThan(warm, .seconds(1))
        print("cold-start=\(cold) warm-start=\(warm)")
    }

    @MainActor
    func testLaunchToReadyWithInjectedEngine() async {
        let engine = MockDictationEngine(coldStartDelay: .milliseconds(10))
        let manager = EngineManager(preferred: .apple, parakeet: engine, apple: engine)

        let launchStarted = ContinuousClock.now
        let ready = await manager.warmActiveEngine()
        let launchToReady = launchStarted.duration(to: .now)

        XCTAssertTrue(ready)
        XCTAssertTrue(manager.activeEngineReady)
        let startCount = await engine.startCount
        XCTAssertEqual(startCount, 1)
        XCTAssertGreaterThan(launchToReady, .zero)
        print("launch-to-ready=\(launchToReady)")
    }

    @MainActor
    func testWarmEngineTimeoutSurfacesRelaunchState() async {
        let engine = MockDictationEngine(ignoresCancellation: true)
        let manager = EngineManager(
            preferred: .apple, parakeet: engine, apple: engine,
            warmUpTimeoutSeconds: 0.05)

        let startedAt = ContinuousClock.now
        let ready = await manager.warmActiveEngine()
        let elapsed = startedAt.duration(to: .now)

        XCTAssertFalse(ready)
        XCTAssertFalse(manager.activeEngineReady)
        XCTAssertTrue(manager.preparationFailed)
        XCTAssertTrue(manager.preparationTimedOut)
        XCTAssertTrue(manager.statusLine.contains("relaunch"))
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testFnReleaseToPasteWithMockEngine() async throws {
        let engine = MockDictationEngine(finishDelay: .milliseconds(10))
        try await engine.start() // Engine warm before Fn release, like the app.

        let pasteSink = MockPasteSink()
        let release = ContinuousClock.now
        try await engine.append(samples: [Float](repeating: 0, count: 336))
        let transcript = try await engine.finish()
        await pasteSink.paste(transcript)
        let releaseToPaste = release.duration(to: .now)

        let pastedText = await pasteSink.text
        let appendCount = await engine.appendCount
        let finishCount = await engine.finishCount
        XCTAssertEqual(pastedText, "hello from mock")
        XCTAssertEqual(appendCount, 1)
        XCTAssertEqual(finishCount, 1)
        XCTAssertGreaterThan(releaseToPaste, .zero)
        print("fn-release-to-paste=\(releaseToPaste)")
    }
}
