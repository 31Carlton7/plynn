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
        /// A meeting is being recorded; `elapsed` is whole seconds so far.
        case meeting(elapsed: Int)
        /// Meeting ended, transcript saved, notes being written in the background.
        case meetingSaved
    }
    public var phase: Phase = .recording(handsFree: false)
    /// Number of envelope points held across the width of the waveform.
    public static let levelHistory = 56
    /// Recent loudness, oldest first. The wave is drawn from this, so what you
    /// said a moment ago travels leftward as you keep talking.
    public private(set) var levels = [Float](repeating: 0, count: levelHistory)
    /// Smoothed peak — fast attack, quick release.
    public private(set) var level: Float = 0
    public var partial: String = ""
    /// Set by the app layer; invoked when the capsule is clicked (stops hands-free).
    public var onTap: (() -> Void)?

    public init() {}

    /// Append envelope points, dropping the oldest to keep the window fixed.
    public func push(levels points: [Float]) {
        guard !points.isEmpty else { return }
        var next = levels
        next.append(contentsOf: points)
        if next.count > Self.levelHistory {
            next.removeFirst(next.count - Self.levelHistory)
        }
        levels = next
        // Snap up to a new peak, ease down from an old one — a meter that
        // decays as slowly as it rises reads as sluggish.
        level = max(points.max() ?? 0, level * 0.78)
    }

    public func resetLevels() {
        levels = [Float](repeating: 0, count: Self.levelHistory)
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
        positionBottomCenter()
        orderFrontRegardless()
    }

    public func hide() {
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
