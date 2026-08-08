import AppKit
import Carbon.HIToolbox

/// Polls Secure Event Input (password fields, Terminal's "Secure Keyboard
/// Entry") at 1 Hz — there is no notification API. Fires only on transitions.
@MainActor
public final class SecureInputWatcher {
    public var onChange: ((Bool) -> Void)?
    private var timer: Timer?
    private var lastValue = false

    public init() {}

    public func start() {
        lastValue = IsSecureEventInputEnabled()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let now = IsSecureEventInputEnabled()
        guard now != lastValue else { return }
        lastValue = now
        onChange?(now)
    }
}
