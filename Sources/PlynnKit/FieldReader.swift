import AppKit
import ApplicationServices

/// Reads the text of the focused UI element via Accessibility — used to see
/// what the user's correction pass did to a paste. Local-only; secure fields
/// are never read.
public enum FieldReader {
    @MainActor
    public static func focusedFieldValue() -> String? {
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

        var valueRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success
        else { return nil }
        return valueRef as? String
    }
}
