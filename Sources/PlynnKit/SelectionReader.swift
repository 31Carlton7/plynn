import AppKit
import ApplicationServices

/// Reads the current text selection from the focused UI element — the entry
/// into command mode. Secure fields and empty selections return nil.
public enum SelectionReader {
    @MainActor
    public static func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if roleRef as? String == "AXSecureTextField" { return nil }

        var selectionRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextAttribute as CFString, &selectionRef) == .success,
            let selection = selectionRef as? String,
            !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return selection
    }
}
