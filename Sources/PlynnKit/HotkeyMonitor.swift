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
    private var healthTimer: Timer?
    private var tapSource: CFRunLoopSource?
    private var tapCreatedTrusted = false
    private var loggedUntrusted = false

    public init(trigger: HotkeyTrigger = .fn) {
        self.trigger = trigger
    }

    /// Creates the tap and keeps it alive: macOS can disable a tap without
    /// delivering the disabled event, and a tap can't exist until
    /// Accessibility is granted. Both are retried every two seconds.
    public func start() -> Bool {
        if healthTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkHealth() }
            }
            RunLoop.main.add(timer, forMode: .common)
            healthTimer = timer
        }
        return createTap()
    }

    private func checkHealth() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            if !loggedUntrusted {
                NSLog("plynn: Accessibility not granted — fn can't be heard until it is")
                loggedUntrusted = true
            }
            return
        }
        loggedUntrusted = false
        // A tap created before Accessibility was granted exists but never
        // receives events, even after the grant. Replace it.
        if tap != nil, !tapCreatedTrusted {
            removeTap()
        }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                NSLog("plynn: hotkey listener was switched off by macOS — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
                resyncReleasedKey()
            }
        } else if createTap() {
            NSLog("plynn: hotkey listener started after Accessibility was granted")
        }
    }

    private func removeTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
        resyncReleasedKey()
    }

    private func resyncReleasedKey() {
        if fnIsDown && !NSEvent.modifierFlags.contains(trigger.nsFlag) {
            fnIsDown = false
            onFnUp?()
        }
    }

    private func createTap() -> Bool {
        guard tap == nil else { return true }
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
        tapCreatedTrusted = AXIsProcessTrusted()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        tapSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("plynn: hotkey listener disabled (%@) — re-enabling",
                  type == .tapDisabledByTimeout ? "timeout" : "user input")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // The tap was deaf for a moment. If fn was released during that
            // window the fnUp is simply gone: this monitor still believes fn
            // is held, so it will emit nothing on the next press and the
            // session stays open forever. Resync against the live flags.
            resyncReleasedKey()
            return
        }
        // The tap's run-loop source is attached to the MAIN run loop, so this
        // callback already executes on the main thread — invoke closures directly.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged && trigger.matches(keycode: keycode) {
            let down = event.flags.contains(trigger.flagMask)
            if down && !fnIsDown {
                fnIsDown = true
                NSLog("plynn: hotkey down")
                onFnDown?()
            } else if !down && fnIsDown {
                fnIsDown = false
                NSLog("plynn: hotkey up")
                onFnUp?()
            }
        } else if type == .keyDown {
            onKeyDown?(keycode)
        }
    }
}
