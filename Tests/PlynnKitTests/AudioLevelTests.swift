import XCTest
@testable import PlynnKit

final class AudioLevelTests: XCTestCase {
    /// Several envelope points per audio callback is the whole point — one
    /// value per buffer moves the visualiser at ~12 Hz and reads as laggy.
    func testEnvelopeSplitsChunkIntoWindows() {
        let samples = [Float](repeating: 0.5, count: 1_000)
        let points = AudioLevel.envelope(of: samples, windowSize: 336)
        XCTAssertEqual(points.count, 3, "1000 samples / 336 = 2 full + 1 partial window")
        for point in points {
            XCTAssertEqual(point, 0.5, accuracy: 0.001, "constant input → constant RMS")
        }
    }

    func testEnvelopeTracksLoudnessAcrossTheChunk() {
        // Quiet first half, loud second half.
        let samples = [Float](repeating: 0.01, count: 320)
            + [Float](repeating: 0.4, count: 320)
        let points = AudioLevel.envelope(of: samples, windowSize: 320)
        XCTAssertEqual(points.count, 2)
        XCTAssertLessThan(points[0], points[1], "envelope should follow the audio")
    }

    func testEnvelopeHandlesDegenerateInput() {
        XCTAssertTrue(AudioLevel.envelope(of: [], windowSize: 336).isEmpty)
        XCTAssertTrue(AudioLevel.envelope(of: [0.1, 0.2], windowSize: 0).isEmpty)
        // A window larger than the chunk still yields one point, not a crash.
        XCTAssertEqual(AudioLevel.envelope(of: [0.5, 0.5], windowSize: 4_096).count, 1)
    }

    func testNormalizedSpreadsSpeechAcrossTheRange() {
        XCTAssertEqual(AudioLevel.normalized(rms: 0), 0, "silence pins to the floor")
        // −50 dBFS floor, −10 dBFS ceiling.
        XCTAssertEqual(AudioLevel.normalized(rms: 0.00316), 0, accuracy: 0.02)
        XCTAssertEqual(AudioLevel.normalized(rms: 0.316), 1, accuracy: 0.02)

        // The reason for the dB mapping: quiet-but-audible speech has to be
        // visibly off the floor, and loud speech must not sit pinned at 1.
        let quiet = AudioLevel.normalized(rms: 0.02)
        let normal = AudioLevel.normalized(rms: 0.08)
        let loud = AudioLevel.normalized(rms: 0.25)
        XCTAssertGreaterThan(quiet, 0.15, "normal talking should not hug the floor")
        XCTAssertLessThan(loud, 1.0, "loud talking should still have headroom")
        XCTAssertLessThan(quiet, normal)
        XCTAssertLessThan(normal, loud)
    }

    func testNormalizedClampsBeyondTheRange() {
        XCTAssertEqual(AudioLevel.normalized(rms: 10), 1)
        XCTAssertEqual(AudioLevel.normalized(rms: 0.000001), 0)
    }

    func testModelKeepsHistoryWindowFixed() async {
        await MainActor.run {
            let model = IndicatorModel()
            XCTAssertEqual(model.levels.count, IndicatorModel.levelHistory)

            model.push(levels: [Float](repeating: 0.9, count: 200))
            XCTAssertEqual(
                model.levels.count, IndicatorModel.levelHistory,
                "history must stay bounded however many points arrive")
            XCTAssertEqual(model.levels.last, 0.9)

            // Fast attack, quick release.
            model.push(levels: [0])
            XCTAssertLessThan(model.level, 0.9)
            XCTAssertGreaterThan(model.level, 0, "release should decay, not cut out")

            model.resetLevels()
            XCTAssertEqual(model.level, 0)
            XCTAssertTrue(model.levels.allSatisfy { $0 == 0 })
        }
    }
}
