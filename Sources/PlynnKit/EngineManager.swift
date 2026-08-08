import FluidAudio
import Foundation

public enum EngineChoice: String, CaseIterable, Sendable {
    case auto, parakeet, apple

    /// Pure selection: preferred engine when usable, Apple otherwise.
    public static func select(preferred: EngineChoice, parakeetReady: Bool) -> EngineChoice {
        switch preferred {
        case .apple: return .apple
        case .parakeet, .auto: return parakeetReady ? .parakeet : .apple
        }
    }

    /// FluidAudio's cache convention: <base>/parakeet-unified*/<something>.mlmodelc
    public static func parakeetModelsPresent(in base: URL? = nil) -> Bool {
        let dir = base
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FluidAudio/Models", isDirectory: true)
        let fm = FileManager.default
        guard let repos = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return false }
        for repo in repos where repo.lastPathComponent.hasPrefix("parakeet-unified") {
            if let files = try? fm.contentsOfDirectory(at: repo, includingPropertiesForKeys: nil),
                files.contains(where: { $0.pathExtension == "mlmodelc" }) {
                return true
            }
        }
        return false
    }
}

/// Owns both engines; picks per-session (never mid-session), and downloads
/// Parakeet in the background when absent, publishing progress for the UI.
@MainActor @Observable
public final class EngineManager {
    public let parakeet = StreamingTranscriber()
    public let apple = AppleSpeechEngine()

    public var preferred: EngineChoice {
        didSet { UserDefaults.standard.set(preferred.rawValue, forKey: "engineChoice") }
    }
    public private(set) var parakeetReady: Bool
    /// 0…1 while the background download runs; nil when idle/complete.
    public private(set) var downloadProgress: Double?

    public init() {
        preferred = EngineChoice(
            rawValue: UserDefaults.standard.string(forKey: "engineChoice") ?? "auto") ?? .auto
        parakeetReady = EngineChoice.parakeetModelsPresent()
        if !parakeetReady { downloadParakeet() }
    }

    public var activeChoice: EngineChoice {
        EngineChoice.select(preferred: preferred, parakeetReady: parakeetReady)
    }

    /// Engine to use for a session that starts now. Warm it via start() upstream.
    public func engineForNewSession() -> any DictationEngine {
        activeChoice == .parakeet ? parakeet : apple
    }

    public var statusLine: String {
        if let p = downloadProgress {
            return "Apple engine — Parakeet downloading \(Int(p * 100))%"
        }
        return activeChoice == .parakeet ? "Parakeet (local)" : "Apple (built-in)"
    }

    private func downloadParakeet() {
        downloadProgress = 0
        let parakeet = parakeet
        Task {
            // StreamingTranscriber.start() triggers the model download via
            // FluidAudio. Poll the cache for coarse progress (file count based
            // progress handlers aren't exposed through the streaming manager).
            let poll = Task { @MainActor [weak self] in
                while self?.downloadProgress != nil {
                    try? await Task.sleep(for: .seconds(2))
                    if EngineChoice.parakeetModelsPresent() { break }
                }
            }
            try? await parakeet.start()
            poll.cancel()
            await MainActor.run { [weak self] in
                self?.downloadProgress = nil
                self?.parakeetReady = EngineChoice.parakeetModelsPresent()
            }
        }
    }
}
