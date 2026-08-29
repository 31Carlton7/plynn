@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit

/// Captures a meeting: your microphone AND the other side of the call
/// (system audio), via one ScreenCaptureKit stream. Both feeds are already
/// time-aligned by SCK, resampled to 16 kHz mono here, and summed into one
/// track for the ASR.
///
/// SCK's audio tap requires the Screen Recording permission even though we
/// never look at a pixel — the stream is configured with a 2×2 frame at
/// 1 fps and no video output is attached.
public final class MeetingRecorder: NSObject, @unchecked Sendable {
    public enum RecorderError: Error {
        case permissionDenied, noDisplay, streamFailed(String)
    }

    /// Summed 16 kHz mono chunks; called on the SCK sample queue.
    public var onChunk: (([Float]) -> Void)?
    /// Called if the stream dies mid-meeting (device change, permission revoked).
    public var onFailure: ((Error) -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "co.charmtechnologies.plynn.meeting")
    /// One resampler per source; each source has its own native format.
    private final class Resample {
        var converter: AVAudioConverter?
        var format: AVAudioFormat?
    }
    private let micResample = Resample()
    private let sysResample = Resample()
    /// Pending resampled samples per source, drained by mixing.
    private var micPending: [Float] = []
    private var sysPending: [Float] = []
    private let mixLock = NSLock()
    public private(set) var startedAt: Date?

    public override init() {}

    /// Ask for permission and start capturing. Throws if the user denies
    /// Screen Recording (macOS shows its own prompt the first time).
    public func start() async throws {
        // Requesting shareable content is what triggers the TCC prompt; it
        // throws when access is denied.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        } catch {
            throw RecorderError.permissionDenied
        }
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        // Exclude our own process so a Plynn sound effect never lands in the notes.
        let me = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        config.captureMicrophone = true
        // Minimal video so SCK doesn't burn a GPU on frames nobody reads.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        do {
            try await stream.startCapture()
        } catch {
            throw RecorderError.streamFailed(error.localizedDescription)
        }
        self.stream = stream
        startedAt = Date()
    }

    public func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        // Flush whatever is left in either buffer.
        mix(flush: true)
    }

    public var elapsed: TimeInterval {
        startedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    // MARK: Mixing

    /// Sum equal-length prefixes of the two pending buffers into one chunk.
    /// If one side has fallen far behind (e.g. system audio silent), don't
    /// hold the other hostage: past a threshold, emit what we have.
    private func mix(flush: Bool = false) {
        mixLock.lock()
        let n = flush
            ? max(micPending.count, sysPending.count)
            : min(micPending.count, sysPending.count)
        guard n > 0 else { mixLock.unlock(); return }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let a = i < micPending.count ? micPending[i] : 0
            let b = i < sysPending.count ? sysPending[i] : 0
            out[i] = max(-1, min(1, a + b))
        }
        micPending.removeFirst(min(n, micPending.count))
        sysPending.removeFirst(min(n, sysPending.count))
        mixLock.unlock()
        onChunk?(out)
    }

    /// Emit unilateral audio if one side is starving the other beyond ~1 s.
    private func drainIfLopsided() {
        mixLock.lock()
        let lopsided = abs(micPending.count - sysPending.count) > 16_000
        mixLock.unlock()
        if lopsided { mix(flush: true) }
    }
}

extension MeetingRecorder: SCStreamOutput, SCStreamDelegate {
    public func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio || type == .microphone,
            let samples = Self.floats16k(
                from: sampleBuffer, using: type == .audio ? sysResample : micResample)
        else { return }
        mixLock.lock()
        if type == .audio { sysPending.append(contentsOf: samples) }
        else { micPending.append(contentsOf: samples) }
        mixLock.unlock()
        mix()
        drainIfLopsided()
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure?(error)
    }

    /// CMSampleBuffer (any PCM layout) → 16 kHz mono Float32.
    private static func floats16k(from sb: CMSampleBuffer, using r: Resample) -> [Float]? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sb),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)?.pointee
        else { return nil }
        guard let inFmt = AVAudioFormat(streamDescription: withUnsafePointer(to: asbd) { $0 })
        else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sb))
        guard frames > 0, let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: frames)
        else { return nil }
        inBuf.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sb, at: 0, frameCount: Int32(frames), into: inBuf.mutableAudioBufferList)
        guard status == noErr else { return nil }

        if inFmt == AudioFile.targetFormat {
            return Array(UnsafeBufferPointer(start: inBuf.floatChannelData![0], count: Int(frames)))
        }
        if r.format != inFmt || r.converter == nil {
            r.converter = AVAudioConverter(from: inFmt, to: AudioFile.targetFormat)
            r.format = inFmt
        }
        guard let conv = r.converter else { return nil }
        let ratio = AudioFile.targetFormat.sampleRate / inFmt.sampleRate
        let cap = AVAudioFrameCount((Double(frames) * ratio).rounded(.up) + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: AudioFile.targetFormat, frameCapacity: cap)
        else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        guard err == nil, let data = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }
}
