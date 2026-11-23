import AppKit
import Carbon.HIToolbox

/// A key bound to one of Plynn's actions: either a modifier held on its own
/// (fn, Right Command) or a combination like ⌥Space.
public struct Shortcut: Hashable, Sendable, RawRepresentable {
    public let keyCode: UInt16
    /// Only ⌘ ⌥ ⌃ ⇧. fn is left out: arrow and function keys report it on
    /// their own, and Carbon hot keys have no fn modifier to register.
    public let modifiers: NSEvent.ModifierFlags

    public static let comboModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    public static let fn = Shortcut(keyCode: 63)

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.modifiers = Self.holdableModifiers[keyCode] == nil
            ? modifiers.intersection(Self.comboModifiers) : []
    }

    /// Stored as "keyCode:modifierFlags", e.g. "49:524288" for ⌥Space.
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let code = UInt16(parts[0]), let flags = UInt(parts[1])
        else { return nil }
        self.init(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: flags))
    }

    public var rawValue: String { "\(keyCode):\(modifiers.rawValue)" }

    /// Modifiers that can be held alone to dictate, with the flag that reports
    /// each one's state on flagsChanged. Left and right share a flag, so the
    /// keycode is what makes these side-specific.
    ///
    /// fn reports a private Globe HID usage that only Apple keyboards send
    /// reliably. Many third-party boards (NuPhy, compact 65%/75% boards) make
    /// their Fn a firmware layer key macOS never sees, which is why the
    /// right-hand modifiers are offered as well.
    static let holdableModifiers: [UInt16: (name: String, flag: CGEventFlags)] = [
        63: ("fn (Globe)", .maskSecondaryFn),
        61: ("Right Option", .maskAlternate),
        54: ("Right Command", .maskCommand),
        62: ("Right Control", .maskControl),
        60: ("Right Shift", .maskShift),
    ]

    /// Left Command, Shift, Option and Control.
    static let leftModifierKeyCodes: Set<UInt16> = [55, 56, 58, 59]

    public var isModifierOnly: Bool { Self.holdableModifiers[keyCode] != nil }

    var holdFlag: CGEventFlags? { Self.holdableModifiers[keyCode]?.flag }

    var carbonModifiers: UInt32 {
        var carbon = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        return UInt32(carbon)
    }

    /// Why this can't be bound to `action`, or nil when it can.
    public func problem(for action: HotkeyAction, among shortcuts: [HotkeyAction: Shortcut]) -> String? {
        if let other = shortcuts.first(where: { $0.key != action && $0.value == self })?.key {
            return "Already used for \(other.title)."
        }
        if Self.leftModifierKeyCodes.contains(keyCode) {
            return "Left-side modifiers are used for other shortcuts. Try fn or a right-side key."
        }
        if isModifierOnly {
            return action.allowsModifierOnly ? nil : "Add a key, like ⌥Space."
        }
        if keyCode == UInt16(kVK_Escape) {
            return "Escape cancels dictation, so it can't start it."
        }
        if modifiers.isDisjoint(with: [.command, .option, .control]) && !isFunctionKey {
            return "Add ⌘, ⌥ or ⌃ so the shortcut doesn't type."
        }
        return nil
    }

    var isFunctionKey: Bool { Self.functionKeyNames[keyCode] != nil }

    public var displayName: String {
        if let held = Self.holdableModifiers[keyCode] { return held.name }
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + keyName
    }

    private var keyName: String {
        if let name = Self.functionKeyNames[keyCode] ?? Self.specialKeyNames[keyCode] {
            return name
        }
        return Self.layoutCharacter(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    private static let specialKeyNames: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "⌦", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]

    private static let functionKeyNames: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]

    /// What the key prints on the current keyboard layout, so ⌥Z reads ⌥Y on
    /// a German layout instead of trusting the US position.
    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layout).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode,
                UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Something in Plynn a shortcut can trigger.
public enum HotkeyAction: String, CaseIterable, Identifiable, Sendable {
    /// Hold to talk; double-tap locks hands-free, triple-tap starts meeting notes.
    case dictate
    /// Press to start dictating without holding anything; press again to stop.
    case handsFree
    case meetingNotes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dictate: return "Hold to dictate"
        case .handsFree: return "Hands-free dictation"
        case .meetingNotes: return "Meeting notes"
        }
    }

    var allowsModifierOnly: Bool { self == .dictate }

    public var defaultShortcut: Shortcut? {
        switch self {
        case .dictate: return .fn
        case .handsFree, .meetingNotes: return nil
        }
    }

    public var defaultsKey: String { "shortcut.\(rawValue)" }

    /// The shortcut saved in Settings, else the default. Dictation also honours
    /// the activation key picked before shortcuts could be recorded.
    public func shortcut(in defaults: UserDefaults = .standard) -> Shortcut? {
        if let raw = defaults.string(forKey: defaultsKey) { return Shortcut(rawValue: raw) }
        if self == .dictate, let legacy = defaults.string(forKey: "hotkeyTrigger") {
            return Self.legacyActivationKeys[legacy] ?? .fn
        }
        return defaultShortcut
    }

    public func resetShortcut(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
        if self == .dictate { defaults.removeObject(forKey: "hotkeyTrigger") }
    }

    public static func storedShortcuts(in defaults: UserDefaults = .standard) -> [HotkeyAction: Shortcut] {
        var shortcuts: [HotkeyAction: Shortcut] = [:]
        for action in allCases {
            shortcuts[action] = action.shortcut(in: defaults)
        }
        return shortcuts
    }

    /// Values of the old "hotkeyTrigger" picker.
    static let legacyActivationKeys: [String: Shortcut] = [
        "fn": .fn,
        "rightOption": Shortcut(keyCode: 61),
        "rightCommand": Shortcut(keyCode: 54),
        "rightControl": Shortcut(keyCode: 62),
    ]
}
