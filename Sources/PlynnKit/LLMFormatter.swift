import Foundation
import MLXLLM
import MLXLMCommon

/// AI polish: filler removal, backtrack self-correction, list formatting,
/// tone matching — Qwen3-4B 4-bit via MLX on the GPU (never contends with the
/// ANE-resident ASR). Every failure mode falls back to the input text.
public actor LLMFormatter {
    public static let modelID = "mlx-community/Qwen3-4B-Instruct-2507-4bit"

    private var model: ModelContainer?
    private var loading = false

    public init() {}

    public var ready: Bool { model != nil }

    /// Download (first run, ~2.3 GB), load, and warm the model. Idempotent.
    public func ensureLoaded() async throws {
        guard model == nil, !loading else { return }
        loading = true
        defer { loading = false }
        let container = try await loadModelContainer(id: Self.modelID)
        // One-token warm-up: Metal kernel JIT + weight page-in happen here at
        // launch, not on the user's first dictation.
        let warm = ChatSession(
            container, generateParameters: GenerateParameters(maxTokens: 1, temperature: 0))
        _ = try? await warm.respond(to: "hi")
        model = container
    }

    /// One stateless prompt → raw completion (nil on timeout/error/not loaded).
    public func complete(_ prompt: String) async -> String? {
        guard let model else { return nil }
        return await withTaskTimeout(seconds: 10) {
            let session = ChatSession(
                model,
                generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0))
            return try await session.respond(to: prompt)
        }
    }

    public func format(
        _ text: String, tone: Tone, technical: Bool, preferredSpellings: [String] = []
    ) async -> String {
        let prompt = PolishPrompt.build(
            transcript: text, tone: tone, technical: technical,
            preferredSpellings: preferredSpellings)
        return PolishPrompt.sanitize(await complete(prompt), input: text)
    }

}

/// Run an async operation with a wall-clock timeout; nil on timeout or error.
///
/// The operation runs *unstructured* on purpose. A task group awaits every
/// child before it returns, and `cancelAll()` only requests cancellation — so
/// one operation that doesn't honour it (FoundationModels can block well past
/// its deadline) would hold the "timeout" open indefinitely and strand the
/// caller. Racing an abandoned task against the sleep means the deadline
/// always wins on time; a straggler finishes into the void and is discarded.
func withTaskTimeout<T: Sendable>(
    seconds: Double, _ operation: @escaping @Sendable () async throws -> T
) async -> T? {
    let box = FirstResult<T>()
    let work = Task { await box.settle(try? await operation()) }
    let timer = Task {
        try? await Task.sleep(for: .seconds(seconds))
        await box.settle(nil)
    }
    let value = await box.value()
    work.cancel()  // best effort — honoured only if the operation checks
    timer.cancel()
    return value
}

/// One-shot race box: whoever settles first wins, later settles are ignored.
private actor FirstResult<T: Sendable> {
    private var value: T?
    private var settled = false
    private var waiter: CheckedContinuation<T?, Never>?

    func settle(_ newValue: T?) {
        guard !settled else { return }
        settled = true
        value = newValue
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: newValue)
        }
    }

    func value() async -> T? {
        if settled { return value }
        return await withCheckedContinuation { continuation in
            // Runs synchronously on this actor, so `settled` cannot flip here.
            if settled { continuation.resume(returning: value) }
            else { waiter = continuation }
        }
    }
}
