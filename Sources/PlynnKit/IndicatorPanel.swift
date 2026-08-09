import AppKit
import SwiftUI

/// Observable UI state for the floating indicator.
@MainActor @Observable
public final class IndicatorModel {
    public enum Phase: Equatable {
        case recording(handsFree: Bool)
        case transcribing
        /// Success state: capsule closes in and a check mark draws on.
        case done
        case secure
        /// The mic couldn't be opened (another app holds a reconfiguring device).
        case micUnavailable
    }
    public var phase: Phase = .recording(handsFree: false)
    public var level: Float = 0
    public var partial: String = ""
    /// Set by the app layer; invoked when the capsule is clicked (stops hands-free).
    public var onTap: (() -> Void)?

    public init() {}
}

/// Always-on-top, non-activating floating capsule. Never steals focus from the
/// dictation target — that is the entire game.
@MainActor
public final class IndicatorPanel: NSPanel {
    private let model: IndicatorModel

    public init(model: IndicatorModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 368, height: 60),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: IndicatorView(model: model))
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public func show() {
        positionBottomCenter()
        orderFrontRegardless()
    }

    public func hide() {
        orderOut(nil)
    }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: f.midX - frame.width / 2,
            y: f.minY + 60))
    }
}
