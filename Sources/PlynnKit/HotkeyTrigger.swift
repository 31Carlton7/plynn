import AppKit

/// Which physical key activates dictation.
///
/// fn is Apple's own key — it reports a private Globe HID usage that only
/// Apple keyboards send reliably. Many third-party keyboards (NuPhy, compact
/// 65%/75% boards especially) implement their own "Fn" as a local firmware
/// layer-shift with no discrete keycode macOS ever sees, so `HotkeyMonitor`
/// hard-wired to fn's keycode never fires on them. The other cases are plain
/// modifier keys every keyboard reports the same way, as a working fallback.
public enum HotkeyTrigger: String, CaseIterable, Identifiable, Sendable {
    case fn
    case rightOption
    case rightCommand
    case rightControl

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fn: return "fn (Globe)"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .rightControl: return "Right Control"
        }
    }

    /// macOS virtual keycode reported on flagsChanged for this key.
    var keycode: Int64 {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        }
    }

    /// The CGEventFlags bit that reflects this key's held state. Left/right
    /// share a bit — the keycode check above is what makes this side-specific.
    var flagMask: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        }
    }

    /// Coarser NSEvent equivalent, used only for the tap-resync fallback path.
    var nsFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .rightOption: return .option
        case .rightCommand: return .command
        case .rightControl: return .control
        }
    }

    func matches(keycode incoming: Int64) -> Bool { incoming == keycode }
}
