import Foundation

/// Upstream this wrapped FluidAudio's Parakeet streaming manager. On Intel
/// Sequoia the same `DictationEngine` surface is Apple's on-device recognizer.
public typealias StreamingTranscriber = AppleSpeechEngine
