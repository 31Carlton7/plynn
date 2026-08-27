import Foundation

/// Context captured at the hotkey boundary for one formatting pass.
///
/// File candidates contain names only. Plynn does not read file contents,
/// surrounding field text, screenshots, or network data.
public struct ContextSnapshot: Equatable, Sendable {
    public let bundleID: String?
    public let selectedText: String?
    public let workspaceRoot: String?
    public let fileCandidates: [String]

    public init(
        bundleID: String? = nil,
        selectedText: String? = nil,
        workspaceRoot: String? = nil,
        fileCandidates: [String] = []
    ) {
        self.bundleID = bundleID
        self.selectedText = selectedText
        self.workspaceRoot = workspaceRoot
        self.fileCandidates = fileCandidates
    }

    public var profile: AppCategories.Profile {
        AppCategories.profile(forBundleID: bundleID)
    }

    public func withFileCandidates(_ fileCandidates: [String]) -> ContextSnapshot {
        ContextSnapshot(
            bundleID: bundleID,
            selectedText: selectedText,
            workspaceRoot: workspaceRoot,
            fileCandidates: fileCandidates)
    }
}
