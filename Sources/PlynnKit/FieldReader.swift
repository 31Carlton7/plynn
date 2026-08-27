import AppKit
import ApplicationServices

/// Reads the text of the focused UI element via Accessibility — used to see
/// what the user's correction pass did to a paste. Local-only; secure fields
/// are never read.
public enum FieldReader {
    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea",
    ]

    @MainActor
    static func isSecureField(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if roleRef as? String == "AXSecureTextField" {
            return true
        }

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        return subroleRef as? String == "AXSecureTextField"
    }

    @MainActor
    public static func focusedFieldAvailable() -> Bool {
        guard let element = focusedElement() else { return false }
        guard !isSecureField(element) else { return false }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element, kAXValueAttribute as CFString, &settable) == .success {
            return settable.boolValue
        }
        return editableRoles.contains(role ?? "")
    }

    @MainActor
    public static func focusedFieldValue() -> String? {
        guard let element = focusedElement() else { return nil }
        guard !isSecureField(element) else { return nil }

        var valueRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success
        else { return nil }
        return valueRef as? String
    }

    @MainActor
    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        return focusedRef as! AXUIElement
    }
}
