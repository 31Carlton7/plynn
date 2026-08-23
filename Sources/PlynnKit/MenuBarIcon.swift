import SwiftUI
import AppKit

/// Plynn's own capsule mark for the menu bar — the same silhouette as the
/// floating dictation indicator, reduced to a bold monochrome glyph so the
/// status item reads as Plynn rather than a generic system symbol.
public enum MenuBarState: Sendable, Equatable {
    case idle, recording, meeting, transcribing
}

private struct MenuBarGlyph: Shape {
    let state: MenuBarState

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let capsule = Capsule(style: .continuous).path(in: rect)

        switch state {
        case .idle:
            // Outline pill + three bars — calm, ready.
            path.addPath(capsule.strokedPath(StrokeStyle(lineWidth: rect.height * 0.15)))
            path.addPath(bars(in: rect, heights: [0.34, 0.58, 0.34]))

        case .recording:
            // Solid pill, bars knocked out as negative space — the standard
            // outline-idle / filled-active flip, legible at 18pt in one tone.
            path.addPath(capsule)
            return path.subtracting(bars(in: rect, heights: [0.30, 0.62, 0.30], widen: true))

        case .meeting:
            // Solid pill, one dot knocked out — a recording light, not a waveform.
            let d = rect.height * 0.3
            let dot = Circle().path(in: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d))
            path.addPath(capsule)
            return path.subtracting(dot)

        case .transcribing:
            // Outline pill + three dots — the same ellipsis language as the
            // "Polishing…" label, so "working" reads the same everywhere.
            path.addPath(capsule.strokedPath(StrokeStyle(lineWidth: rect.height * 0.15)))
            let d = rect.height * 0.16
            for fx in [0.32, 0.5, 0.68] {
                let cx = rect.width * fx
                path.addPath(Circle().path(in: CGRect(x: cx - d / 2, y: rect.midY - d / 2, width: d, height: d)))
            }
        }
        return path
    }

    private func bars(in rect: CGRect, heights: [Double], widen: Bool = false) -> Path {
        var path = Path()
        let barWidth = rect.width * (widen ? 0.15 : 0.12)
        let gap = rect.width * 0.10
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        var x = rect.midX - totalWidth / 2
        for h in heights {
            let barHeight = rect.height * h
            let barRect = CGRect(x: x, y: rect.midY - barHeight / 2, width: barWidth, height: barHeight)
            path.addPath(RoundedRectangle(cornerRadius: barWidth / 2).path(in: barRect))
            x += barWidth + gap
        }
        return path
    }
}

public enum MenuBarIcon {
    /// 1.6:1 aspect ratio so the capsule reads as a pill, not a circle —
    /// NSStatusItem sizes its button to whatever width the image reports.
    private static let size = NSSize(width: 24, height: 15)

    @MainActor
    public static func image(for state: MenuBarState) -> NSImage {
        let view = MenuBarGlyph(state: state)
            .fill(.black)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3  // Retina-crisp; NSImage.size below fixes the logical footprint.
        let image = NSImage(size: size)
        if let cg = renderer.cgImage {
            image.addRepresentation(NSBitmapImageRep(cgImage: cg))
        }
        image.isTemplate = true  // macOS re-tints for light/dark menu bars and click state.
        return image
    }
}
