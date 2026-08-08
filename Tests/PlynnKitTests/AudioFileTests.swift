import AVFoundation
import XCTest
@testable import PlynnKit

final class AudioFileTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }

    func testLoadsFixtureAs16kMonoFloats() throws {
        let samples = try AudioFile.loadSamples16kMono(url: fixtureURL("hello.wav"))
        // ~6s sentence → between 2s and 15s of 16k samples
        XCTAssertGreaterThan(samples.count, 32_000)
        XCTAssertLessThan(samples.count, 240_000)
        XCTAssertTrue(samples.contains { abs($0) > 0.01 }, "audio should be non-silent")
    }

    func testResamples48kStereoTo16kMono() throws {
        let inFmt = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 48_000)!
        buf.frameLength = 48_000  // 1 second, 440 Hz sine
        for ch in 0..<2 {
            let p = buf.floatChannelData![ch]
            for i in 0..<48_000 { p[i] = sinf(2 * .pi * 440 * Float(i) / 48_000) }
        }
        let out = try Resampler.convert(buffer: buf, to: AudioFile.targetFormat)
        XCTAssertTrue((15_800...16_200).contains(out.count), "got \(out.count) samples")  // ~1s at 16k
        XCTAssertGreaterThan(out.max() ?? 0, 0.5)
    }
}
