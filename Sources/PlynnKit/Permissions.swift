@preconcurrency import AVFoundation
import AppKit
import ApplicationServices
@preconcurrency import Speech

/// Permission checks and actions. All checks are poll-based — macOS has no
/// grant notifications for Accessibility.
@MainActor
public enum Permissions {
    public static func micGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func speechGranted() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Globe key set to "Do Nothing" (0) so it can't fight Plynn's fn hotkey.
    public static func globeKeySafe() -> Bool {
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        return defaults?.integer(forKey: "AppleFnUsageType") == 0
            && defaults?.object(forKey: "AppleFnUsageType") != nil
    }

    public static func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    public static func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    /// Shows the system Accessibility prompt (once per TCC state).
    public static func promptAccessibility() {
        // kAXTrustedCheckOptionPrompt is a C global Swift 6 won't touch across
        // concurrency domains; its literal value is stable API.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    public static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// User-initiated (explicit button press): set Globe key to Do Nothing.
    public static func setGlobeKeyDoNothing() {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.set(0, forKey: "AppleFnUsageType")
    }

    /// Relaunch the app — required after an Accessibility grant so the event
    /// tap is created under the new TCC state.
    public static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
