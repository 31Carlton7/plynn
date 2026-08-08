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

    public func format(
        _ text: String, tone: Tone, technical: Bool, preferredSpellings: [String] = []
    ) async -> String {
        guard let model else { return text }
        let prompt = PolishPrompt.build(
            transcript: text, tone: tone, technical: technical,
            preferredSpellings: preferredSpellings)
        let result: String? = await withTaskTimeout(seconds: 8) {
            let session = ChatSession(
                model,
                generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0))
            return try await session.respond(to: prompt)
        }
        return PolishPrompt.sanitize(result, input: text)
    }

}

/// Run an async operation with a wall-clock timeout; nil on timeout or error.
func withTaskTimeout<T: Sendable>(
    seconds: Double, _ operation: @escaping @Sendable () async throws -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { try? await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
