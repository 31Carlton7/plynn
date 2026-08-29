import Foundation

public enum EngineChoice: String, CaseIterable, Sendable {
    case auto, parakeet, apple

    /// Sequoia Intel has one engine: Apple's on-device Speech recognizer.
    /// Parakeet/FluidAudio needs the Neural Engine on Apple Silicon.
    public static func select(preferred: EngineChoice, parakeetReady: Bool) -> EngineChoice {
        .apple
    }

    public static func parakeetModelsPresent(in base: URL? = nil) -> Bool {
        false
    }
}

/// Owns the dictation engine. Upstream this also downloaded Parakeet; that
/// path is compiled out on Intel because FluidAudio/ANE are unavailable.
@MainActor @Observable
public final class EngineManager {
    public let apple = AppleSpeechEngine()

    public var preferred: EngineChoice {
        didSet { UserDefaults.standard.set(preferred.rawValue, forKey: "engineChoice") }
    }
    public private(set) var parakeetReady: Bool = false
    public private(set) var downloadProgress: Double?

    public init() {
        preferred = EngineChoice(
            rawValue: UserDefaults.standard.string(forKey: "engineChoice") ?? "apple") ?? .apple
        preferred = .apple
    }

    public var activeChoice: EngineChoice { .apple }

    public func engineForNewSession() -> any DictationEngine {
        apple
    }

    public var statusLine: String {
        "Apple Speech (on-device, Sequoia)"
    }
}
