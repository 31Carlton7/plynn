import AppKit

/// CGEventTap watcher emitting raw key events for whichever key `trigger`
/// names (default fn: flagsChanged keycode 63, .maskSecondaryFn — see
/// `HotkeyTrigger` for why that default doesn't work on every keyboard). All
/// session logic — interruption, double-tap, cancel — lives in the tested
/// `Session` state machine, not here.
public final class HotkeyMonitor {
    public var onFnDown: (() -> Void)?
    public var onFnUp: (() -> Void)?
    /// Any other keyDown (keycode passed; 53 = Escape).
    public var onKeyDown: ((Int64) -> Void)?
    /// Settable at any time — takes effect on the next event, no restart needed.
    public var trigger: HotkeyTrigger

    private var tap: CFMachPort?
    private var fnIsDown = false

    public init(trigger: HotkeyTrigger = .fn) {
        self.trigger = trigger
    }

    public func start() -> Bool {
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // The tap was deaf for a moment. If fn was released during that
            // window the fnUp is simply gone: this monitor still believes fn
            // is held, so it will emit nothing on the next press and the
            // session stays open forever. Resync against the live flags.
            if fnIsDown && !NSEvent.modifierFlags.contains(trigger.nsFlag) {
                fnIsDown = false
                onFnUp?()
            }
            return
        }
        // The tap's run-loop source is attached to the MAIN run loop, so this
        // callback already executes on the main thread — invoke closures directly.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged && trigger.matches(keycode: keycode) {
            let down = event.flags.contains(trigger.flagMask)
            if down && !fnIsDown {
                fnIsDown = true
                onFnDown?()
            } else if !down && fnIsDown {
                fnIsDown = false
                onFnUp?()
            }
        } else if type == .keyDown {
            onKeyDown?(keycode)
        }
    }
}
