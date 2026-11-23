import AppKit
import Carbon.HIToolbox

/// Emits raw key events for the dictation shortcut. A lone modifier (default
/// fn: flagsChanged keycode 63, .maskSecondaryFn) is watched with a
/// CGEventTap; a key combination is registered as a Carbon hot key, which
/// swallows the keystroke so ⌥Space doesn't also type into the focused app.
/// All session logic — interruption, double-tap, cancel — lives in the tested
/// `Session` state machine, not here.
public final class HotkeyMonitor {
    public var onFnDown: (() -> Void)?
    public var onFnUp: (() -> Void)?
    /// Any other keyDown (keycode passed; 53 = Escape).
    public var onKeyDown: ((Int64) -> Void)?
    /// Settable at any time — takes effect on the next event, no restart needed.
    public var shortcuts: [HotkeyAction: Shortcut] {
        didSet { registerHotKeys() }
    }
    /// While Settings records a new shortcut, nothing fires and the hot keys
    /// are released so the recorder can capture the combination itself.
    public var isPaused = false {
        didSet { registerHotKeys() }
    }

    private var tap: CFMachPort?
    private var fnIsDown = false
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []

    public init(shortcuts: [HotkeyAction: Shortcut]) {
        self.shortcuts = shortcuts
    }

    /// Hot keys work without any permission; the tap needs Accessibility.
    public func start() -> Bool {
        installHotKeyHandler()
        registerHotKeys()

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)  // listen, never swallow (Phase 1)
        }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }  // nil = missing Accessibility permission
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let dictation = shortcuts[.dictate]
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // The tap was deaf for a moment. If fn was released during that
            // window the fnUp is simply gone: this monitor still believes fn
            // is held, so it will emit nothing on the next press and the
            // session stays open forever. Resync against the live flags.
            if fnIsDown, let flag = dictation?.holdFlag,
                !CGEventSource.flagsState(.combinedSessionState).contains(flag) {
                fnIsDown = false
                onFnUp?()
            }
            return
        }
        guard !isPaused else { return }
        // The tap's run-loop source is attached to the MAIN run loop, so this
        // callback already executes on the main thread — invoke closures directly.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged, let dictation, let flag = dictation.holdFlag,
            keycode == Int64(dictation.keyCode) {
            let down = event.flags.contains(flag)
            if down && !fnIsDown {
                fnIsDown = true
                onFnDown?()
            } else if !down && fnIsDown {
                fnIsDown = false
                onFnUp?()
            }
        } else if type == .keyDown {
            let pressed = Shortcut(
                keyCode: UInt16(keycode),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
            // A hot key's own keystroke would otherwise read as "fn+something"
            // and interrupt the dictation it just started.
            guard !shortcuts.values.contains(pressed) else { return }
            onKeyDown?(keycode)
        }
    }

    // MARK: Hot keys

    private static let hotKeySignature: OSType = 0x504C_594E  // "PLYN"

    private func installHotKeyHandler() {
        guard hotKeyHandler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                monitor.handleHotKey(
                    index: Int(hotKeyID.id),
                    pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
                return noErr
            },
            eventTypes.count, &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
    }

    private func registerHotKeys() {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        hotKeys = []
        guard !isPaused, hotKeyHandler != nil else { return }
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let shortcut = shortcuts[action], !shortcut.isModifierOnly else { continue }
            var hotKey: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                EventHotKeyID(signature: Self.hotKeySignature, id: UInt32(index)),
                GetApplicationEventTarget(), 0, &hotKey)
            if let hotKey, status == noErr {
                hotKeys.append(hotKey)
            } else {
                NSLog("plynn: could not register %@ for %@ (%d)",
                      shortcut.displayName, action.rawValue, status)
            }
        }
    }

    private func handleHotKey(index: Int, pressed: Bool) {
        guard !isPaused, HotkeyAction.allCases.indices.contains(index) else { return }
        switch HotkeyAction.allCases[index] {
        case .dictate:
            if pressed && !fnIsDown {
                fnIsDown = true
                onFnDown?()
            } else if !pressed && fnIsDown {
                fnIsDown = false
                onFnUp?()
            }
        }
    }
}
