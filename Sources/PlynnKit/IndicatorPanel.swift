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
        /// A dictation engine or paste operation failed; the message remains
        /// visible briefly so the user knows why no text appeared.
        case error(String)
        /// A meeting is being recorded; `elapsed` is whole seconds so far.
        case meeting(elapsed: Int)
        /// Meeting ended, transcript saved, notes being written in the background.
        case meetingSaved
    }
    public var phase: Phase = .recording(handsFree: false)
    /// True only while the panel is on screen. The waveform uses this to
    /// avoid running a TimelineView behind a hidden panel.
    public fileprivate(set) var isVisible = false
    /// Smoothed peak — fast attack, quick release.
    public private(set) var level: Float = 0
    public var partial: String = ""
    /// Set by the app layer; invoked when the capsule is clicked (stops hands-free).
    public var onTap: (() -> Void)?

    public init() {}

    /// Fold in the envelope points from one audio buffer.
    public func push(levels points: [Float]) {
        guard !points.isEmpty else { return }
        // Snap up to a new peak, ease down from an old one — a meter that
        // decays as slowly as it rises reads as sluggish.
        level = max(points.max() ?? 0, level * 0.78)
    }

    public func resetLevels() {
        level = 0
    }
}

/// Always-on-top, non-activating floating capsule. Never steals focus from the
/// dictation target — that is the entire game.
@MainActor
public final class IndicatorPanel: NSPanel {
    private let model: IndicatorModel

    public init(model: IndicatorModel) {
        self.model = model
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: IndicatorMetrics.width + IndicatorMetrics.panelPadding * 2,
                height: IndicatorMetrics.height + IndicatorMetrics.panelPadding * 2),
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
        model.isVisible = true
        positionBottomCenter()
        orderFrontRegardless()
    }

    public func hide() {
        model.isVisible = false
        orderOut(nil)
    }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        // The panel carries panelPadding of transparent slack around the
        // capsule, so subtract it — otherwise the visible gap is that much
        // larger than the number says.
        setFrameOrigin(NSPoint(
            x: f.midX - frame.width / 2,
            y: f.minY + IndicatorMetrics.bottomMargin - IndicatorMetrics.panelPadding))
    }
}
