import AVFoundation
import XCTest
@testable import PlynnKit

final class MeetingRecorderTests: XCTestCase {
    /// The layouts ScreenCaptureKit hands us on macOS 26: 48 kHz mono Float32,
    /// packed for the microphone and non-interleaved for system audio.
    static let micFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
    static let systemFlags = micFlags | kAudioFormatFlagIsNonInterleaved

    func sampleBuffer(
        formatID: AudioFormatID = kAudioFormatLinearPCM, flags: AudioFormatFlags, frames: Int
    ) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: formatID, mFormatFlags: flags,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var fmtDesc: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &fmtDesc), noErr)

        let samples = (0..<frames).map { sinf(2 * .pi * 440 * Float($0) / 48_000) }
        let byteCount = frames * 4
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block), noErr)
        samples.withUnsafeBytes {
            XCTAssertEqual(CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0,
                dataLength: byteCount), noErr)
        }

        var sb: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: fmtDesc!,
            sampleCount: frames, presentationTimeStamp: .zero, packetDescriptions: nil,
            sampleBufferOut: &sb), noErr)
        return try XCTUnwrap(sb)
    }

    func testConvertsMicrophoneLayoutTo16k() throws {
        let sb = try sampleBuffer(flags: Self.micFlags, frames: 512)
        let out = try XCTUnwrap(MeetingRecorder.floats16k(from: sb, using: .init()))
        XCTAssertTrue((160...180).contains(out.count), "got \(out.count) samples")
        XCTAssertGreaterThan(out.max() ?? 0, 0.5)
    }

    func testConvertsSystemAudioLayoutTo16k() throws {
        let sb = try sampleBuffer(flags: Self.systemFlags, frames: 960)
        let out = try XCTUnwrap(MeetingRecorder.floats16k(from: sb, using: .init()))
        XCTAssertTrue((310...330).contains(out.count), "got \(out.count) samples")
        XCTAssertGreaterThan(out.max() ?? 0, 0.5)
    }

    /// One resampler serves a source for the whole meeting.
    func testKeepsConvertingAfterTheFirstBuffer() throws {
        let resample = MeetingRecorder.Resample()
        var total = 0
        for _ in 0..<20 {
            let sb = try sampleBuffer(flags: Self.micFlags, frames: 512)
            total += try XCTUnwrap(MeetingRecorder.floats16k(from: sb, using: resample)).count
        }
        XCTAssertGreaterThan(total, 3_000, "20 × 512 frames at 48 kHz is ~3,413 samples at 16 kHz")
    }

    /// AVAudioPCMBuffer raises an uncaught NSException for a non-PCM format.
    func testDropsNonPCMBuffer() throws {
        let sb = try sampleBuffer(formatID: kAudioFormatAppleLossless, flags: 0, frames: 512)
        XCTAssertNil(MeetingRecorder.floats16k(from: sb, using: .init()))
    }
}
