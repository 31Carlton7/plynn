import Foundation

/// Context captured at the hotkey boundary for one formatting pass.
///
/// This deliberately contains only data Plynn already has safely available:
/// the frontmost application and an optional selection. It does not read the
/// surrounding field, inspect the filesystem, take screenshots, or make a
/// network request.
public struct ContextSnapshot: Equatable, Sendable {
    public let bundleID: String?
    public let selectedText: String?

    public init(bundleID: String? = nil, selectedText: String? = nil) {
        self.bundleID = bundleID
        self.selectedText = selectedText
    }

    public var profile: AppCategories.Profile {
        AppCategories.profile(forBundleID: bundleID)
    }
}
