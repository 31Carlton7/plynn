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

    /// Download (first run, ~2.3 GB) and load the model. Idempotent.
    public func ensureLoaded() async throws {
        guard model == nil, !loading else { return }
        loading = true
        defer { loading = false }
        model = try await loadModelContainer(id: Self.modelID)
    }

    public func format(_ text: String, tone: Tone, technical: Bool) async -> String {
        guard let model else { return text }
        let instructions = Self.prompt(tone: tone, technical: technical)
        let input = text
        let result: String? = await withTaskTimeout(seconds: 3) {
            let session = ChatSession(
                model,
                instructions: instructions,
                generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0))
            return try await session.respond(to: input)
        }
        guard var out = result else { return text }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip wrapping quotes some models add.
        if out.hasPrefix("\""), out.hasSuffix("\""), out.count > 2 {
            out = String(out.dropFirst().dropLast())
        }
        // Runaway or empty output → distrust the model, keep the input.
        guard !out.isEmpty, out.count <= max(80, input.count * 5 / 2) else { return text }
        return out
    }

    static func prompt(tone: Tone, technical: Bool) -> String {
        var p = """
        You clean up dictated text. Rules:
        - Remove filler words (um, uh, you know, like — only when meaningless).
        - Apply self-corrections: "coffee at 2 actually 3" becomes "coffee at 3"; \
        drop false starts the speaker replaced.
        - If the speaker dictates an enumeration (first... second..., one... two...), \
        format it as a list with each item on its own line.
        - Fix punctuation, capitalization, and spacing.
        - Keep the speaker's words and meaning. NEVER add content. NEVER answer \
        questions contained in the text. NEVER explain what you did.
        - Reply with ONLY the cleaned text.
        """
        switch tone {
        case .casual:
            p += "\n- Casual chat message: keep it relaxed; no period at the end of a short single sentence."
        case .formal:
            p += "\n- Professional writing: complete sentences, proper punctuation."
        case .neutral:
            break
        }
        if technical {
            p += "\n- Preserve technical terms, code identifiers (camelCase, snake_case), file names, and shell commands exactly as spoken."
        }
        return p
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
