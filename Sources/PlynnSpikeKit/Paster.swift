import AppKit
import Carbon.HIToolbox

public enum Paster {
    /// Saves the clipboard string, pastes `text` via synthetic Cmd-V, restores after 0.3 s.
    public static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        let savedChangeCount = pb.changeCount

        pb.clearContents()
        // Transient marker so clipboard managers skip the transcript.
        pb.setString(text, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        // Give the pasteboard server a beat before synthesizing Cmd-V (VoiceInk uses 0.1 s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            postCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Only restore if nobody else wrote to the clipboard meanwhile.
                if pb.changeCount == savedChangeCount + 1, let saved {
                    pb.clearContents()
                    pb.setString(saved, forType: .string)
                }
            }
        }
    }

    private static func postCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        for e in [cmdDown, vDown, vUp, cmdUp] { e?.post(tap: .cghidEventTap) }
    }
}
