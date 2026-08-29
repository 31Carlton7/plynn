import Foundation

/// Apple Intelligence polish is unavailable on Intel Sequoia (Foundation
/// Models requires macOS 26 + Apple Silicon). The actor stays so the rest of
/// the formatting pipeline compiles unchanged; every call degrades to the
/// input text, same as the upstream failure path.
public actor AppleFMFormatter {
    public init() {}

    public nonisolated var ready: Bool { false }

    public nonisolated var availabilityDescription: String {
        "Apple Intelligence needs Apple Silicon and macOS 26 — this Sequoia Intel build uses rules-only polish"
    }

    public func warm() {}

    public func complete(_ prompt: String) async -> String? { nil }

    public func format(
        _ text: String, tone: Tone, technical: Bool, preferredSpellings: [String] = []
    ) async -> String {
        text
    }
}
