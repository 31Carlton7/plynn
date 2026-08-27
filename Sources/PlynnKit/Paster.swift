import AppKit
import Carbon.HIToolbox

public enum PasteResult: Equatable, Sendable {
    /// The paste event was constructed and queued; macOS gives no reliable
    /// acknowledgement that the target accepted it.
    case scheduled
    case copiedToClipboard
    case failed
}

public enum Paster {
    /// Preflight the target, then paste `text` via synthetic Cmd-V.
    /// Falls back to leaving the transcript on the clipboard when the target
    /// cannot be inspected or Accessibility is unavailable.
    @MainActor
    public static func paste(
        _ text: String,
        onComplete: (@MainActor @Sendable () -> Void)? = nil,
        onFailure: (@MainActor @Sendable (PasteResult) -> Void)? = nil
    ) -> PasteResult {
        guard Permissions.accessibilityGranted(), FieldReader.focusedFieldAvailable()
        else { return copyToClipboard(text) ? .copiedToClipboard : .failed }

        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        let savedChangeCount = pb.changeCount

        guard pb.clearContents() != 0 else {
            return copyToClipboard(text) ? .copiedToClipboard : .failed
        }
        // Transient marker so clipboard managers skip the transcript.
        guard pb.setString(text, forType: .string) else {
            return copyToClipboard(text) ? .copiedToClipboard : .failed
        }
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        // Give the pasteboard server a beat before synthesizing Cmd-V (VoiceInk uses 0.1 s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard Permissions.accessibilityGranted(), FieldReader.focusedFieldAvailable()
            else {
                let fallback = copyToClipboard(text) ? PasteResult.copiedToClipboard : .failed
                onFailure?(fallback)
                return
            }
            guard postCmdV() else {
                let fallback = copyToClipboard(text) ? PasteResult.copiedToClipboard : .failed
                onFailure?(fallback)
                return
            }
            onComplete?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Only restore if nobody else wrote to the clipboard meanwhile.
                if pb.changeCount == savedChangeCount + 1, let saved {
                    pb.clearContents()
                    pb.setString(saved, forType: .string)
                }
            }
        }
        return .scheduled
    }

    /// Leave text available for an explicit Cmd-V when automatic paste cannot
    /// safely target an editable field.
    @MainActor
    private static func copyToClipboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        guard pb.clearContents() != 0 else { return false }
        return pb.setString(text, forType: .string)
    }

    /// Synthesize a Return keypress (the "press enter" command) — call only
    /// after the paste has landed.
    public static func pressReturn() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    @discardableResult
    private static func postCmdV() -> Bool {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard
            let cmdDown = CGEvent(
                keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
            let vDown = CGEvent(
                keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let vUp = CGEvent(
                keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false),
            let cmdUp = CGEvent(
                keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        else { return false }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        for e in [cmdDown, vDown, vUp, cmdUp] { e.post(tap: .cghidEventTap) }
        return true
    }
}
