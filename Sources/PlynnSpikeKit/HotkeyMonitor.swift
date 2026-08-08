import AppKit

/// CGEventTap watcher for the fn key (flagsChanged, keycode 63, .maskSecondaryFn).
/// Hold = onFnDown/onFnUp. A non-fn key pressed while fn is held marks the hold
/// "interrupted" (user was doing fn+arrow, not dictating) and suppresses onFnUp.
public final class HotkeyMonitor {
    public var onFnDown: (() -> Void)?
    public var onFnUp: (() -> Void)?
    public var onInterrupted: (() -> Void)?

    private var tap: CFMachPort?
    private var fnIsDown = false
    private var interrupted = false

    public init() {}

    public func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)  // listen, never swallow (spike)
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
            return
        }
        // The tap's run-loop source is attached to the MAIN run loop, so this
        // callback already executes on the main thread — invoke closures directly.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged && keycode == 63 {
            let down = event.flags.contains(.maskSecondaryFn)
            if down && !fnIsDown {
                fnIsDown = true; interrupted = false
                onFnDown?()
            } else if !down && fnIsDown {
                fnIsDown = false
                interrupted ? onInterrupted?() : onFnUp?()
            }
        } else if type == .keyDown && fnIsDown {
            interrupted = true  // fn+something = a shortcut, not dictation
        }
    }
}
