@preconcurrency import AVFoundation

public enum AudioFile {
    nonisolated(unsafe) public static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// Reads any audio file and returns 16 kHz mono Float32 samples.
    public static func loadSamples16kMono(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inBuf = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        return try Resampler.convert(buffer: inBuf, to: targetFormat)
    }
}
