import AVFoundation

public enum Resampler {
    public static func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> [Float] {
        if buffer.format == format { return floats(from: buffer) }
        let converter = AVAudioConverter(from: buffer.format, to: format)!
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 1024)
        let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
        var fed = false
        var convError: NSError?
        converter.convert(to: outBuf, error: &convError) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        if let convError { throw convError }
        return floats(from: outBuf)
    }

    private static func floats(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
}
