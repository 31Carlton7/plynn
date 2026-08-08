import Foundation

public enum Tone: String, Sendable, Equatable {
    case casual, neutral, formal
}

/// Frontmost-app → formatting profile, used to steer the LLM polish prompt
/// (Wispr's "Flow Styles", done locally with a bundle-ID map).
public enum AppCategories {
    public struct Profile: Equatable, Sendable {
        public let tone: Tone
        /// Preserve code identifiers, commands, technical jargon verbatim.
        public let isTechnical: Bool
    }

    private static let casual: Set<String> = [
        "com.apple.MobileSMS",          // Messages
        "net.whatsapp.WhatsApp",
        "com.hnc.Discord",
        "ru.keepcoder.Telegram",
        "com.tinyspeck.slackmacgap",    // Slack
        "com.facebook.archon",          // Messenger
    ]

    private static let formal: Set<String> = [
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.readdle.smartemail-Mac",   // Spark
        "com.superhuman.electron",
    ]

    private static let technical: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
        "com.apple.dt.Xcode",
        "com.jetbrains.intellij",
    ]

    public static func profile(forBundleID bundleID: String?) -> Profile {
        guard let bundleID else { return Profile(tone: .neutral, isTechnical: false) }
        if casual.contains(bundleID) { return Profile(tone: .casual, isTechnical: false) }
        if formal.contains(bundleID) { return Profile(tone: .formal, isTechnical: false) }
        if technical.contains(bundleID) { return Profile(tone: .neutral, isTechnical: true) }
        return Profile(tone: .neutral, isTechnical: false)
    }
}
