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
    private enum WarmOutcome: Sendable, Equatable {
        case loaded, failed, timedOut
    }

    public static let defaultWarmUpTimeoutSeconds = 30.0

    public let parakeet: any DictationEngine
    public let apple: any DictationEngine

    public var preferred: EngineChoice {
        didSet {
            UserDefaults.standard.set(preferred.rawValue, forKey: "engineChoice")
            readyChoice = nil
            preparationFailed = false
            preparationTimedOut = false
        }
    }
    public private(set) var parakeetReady: Bool
    /// 0…1 while the background download runs; nil when idle/complete.
    public private(set) var downloadProgress: Double?
    /// Engine choice whose models have completed a successful warm-up.
    public private(set) var readyChoice: EngineChoice?
    public private(set) var preparationFailed = false
    public private(set) var preparationTimedOut = false
    private var warmTask: Task<WarmOutcome, Never>?
    private let warmUpTimeoutSeconds: Double

    public init(
        preferred: EngineChoice? = nil,
        parakeet: (any DictationEngine)? = nil,
        apple: (any DictationEngine)? = nil,
        warmUpTimeoutSeconds: Double = EngineManager.defaultWarmUpTimeoutSeconds
    ) {
        let injectedParakeet = parakeet != nil
        self.parakeet = parakeet ?? StreamingTranscriber()
        self.apple = apple ?? AppleSpeechEngine()
        self.warmUpTimeoutSeconds = max(0, warmUpTimeoutSeconds)
        self.preferred = preferred
            ?? (EngineChoice(
                rawValue: UserDefaults.standard.string(forKey: "engineChoice") ?? "auto") ?? .auto)
        parakeetReady = injectedParakeet || EngineChoice.parakeetModelsPresent()
        if !injectedParakeet && !parakeetReady { downloadParakeet() }
    }

    public var activeChoice: EngineChoice {
        EngineChoice.select(preferred: preferred, parakeetReady: parakeetReady)
    }

    public var activeEngineReady: Bool {
        readyChoice == activeChoice
    }

    /// Engine to use for a session that starts now. Warm it via start() upstream.
    public func engineForNewSession() -> any DictationEngine {
        activeChoice == .parakeet ? parakeet : apple
    }

    public var statusLine: String {
        let name = activeChoice == .parakeet ? "Parakeet (local)" : "Apple (built-in)"
        if activeEngineReady {
            if downloadProgress != nil {
                return "\(name) ready · speech model downloading"
            }
            return "\(name) ready"
        }
        if preparationTimedOut { return "Model startup timed out — relaunch Plynn" }
        if preparationFailed { return "\(name) unavailable — retry" }
        if downloadProgress != nil {
            return "\(name) preparing · speech model downloading"
        }
        return "\(name) preparing…"
    }

    /// Warm the engine selected for the next session, once at a time.
    @discardableResult
    public func warmActiveEngine() async -> Bool {
        if activeEngineReady { return true }
        if let warmTask {
            _ = await warmTask.value
            return activeEngineReady
        }

        let choice = activeChoice
        let engine = engineForNewSession()
        preparationFailed = false
        preparationTimedOut = false
        let timeout = warmUpTimeoutSeconds
        let task = Task { [engine, timeout] () -> WarmOutcome in
            let outcome = await withTaskTimeout(seconds: timeout) {
                do {
                    try await engine.start()
                    return WarmOutcome.loaded
                } catch {
                    NSLog("plynn: engine warm failed (%@): %@", engine.displayName, String(describing: error))
                    return WarmOutcome.failed
                }
            }
            if outcome == nil {
                NSLog("plynn: engine warm timed out (%@) after %.1fs", engine.displayName, timeout)
                return .timedOut
            }
            return outcome!
        }
        warmTask = task
        let outcome = await task.value
        warmTask = nil

        if outcome == .loaded, activeChoice == choice {
            readyChoice = choice
            preparationFailed = false
            preparationTimedOut = false
        } else if activeChoice == choice {
            readyChoice = nil
            preparationFailed = true
            preparationTimedOut = outcome == .timedOut
        }
        return activeEngineReady
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
            var loaded = false
            do {
                try await parakeet.start()
                loaded = true
            } catch {
                NSLog("plynn: Parakeet download/warm failed: %@", String(describing: error))
            }
            poll.cancel()
            await MainActor.run { [weak self] in
                self?.downloadProgress = nil
                self?.parakeetReady = EngineChoice.parakeetModelsPresent()
                if loaded, self?.parakeetReady == true {
                    self?.readyChoice = .parakeet
                    self?.preparationFailed = false
                }
            }
        }
    }
}
