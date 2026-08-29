import Foundation

/// Local Qwen polish via MLX is Apple Silicon + Metal only. On Intel the
/// formatter stays as a no-op so Settings / command mode / meeting notes
/// degrade cleanly instead of linking an unusable GPU runtime.
public actor LLMFormatter {
    public static let modelID = "unavailable-on-intel"

    public init() {}

    public var ready: Bool { false }

    public func ensureLoaded() async throws {}

    public func complete(_ prompt: String) async -> String? { nil }

    public func format(
        _ text: String, tone: Tone, technical: Bool, preferredSpellings: [String] = []
    ) async -> String {
        text
    }
}

/// Run an async operation with a wall-clock timeout; nil on timeout or error.
///
/// The operation runs *unstructured* on purpose. A task group awaits every
/// child before it returns, and `cancelAll()` only requests cancellation — so
/// one operation that doesn't honour it would hold the "timeout" open
/// indefinitely and strand the caller. Racing an abandoned task against the
/// sleep means the deadline always wins on time; a straggler finishes into
/// the void and is discarded.
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
    work.cancel()
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
            if settled { continuation.resume(returning: value) }
            else { waiter = continuation }
        }
    }
}
