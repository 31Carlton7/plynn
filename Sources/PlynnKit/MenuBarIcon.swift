import SwiftUI
import AppKit

/// Plynn's menu bar glyph. At rest it's a plain waveform, the same restraint
/// as an SF Symbol, no container around it. When the mic is actually
/// capturing, a small filled squircle badge appears behind the glyph: the
/// same "feature is active" idiom macOS itself uses for its own screen
/// recording / mic-in-use indicator, so it sits naturally next to it.
public enum MenuBarState: Sendable, Equatable {
    case idle, recording, meeting, transcribing
}

private struct MenuBarGlyph: Shape {
    let state: MenuBarState

    func path(in rect: CGRect) -> Path {
        switch state {
        case .idle:
            return bars(in: rect, heights: [0.40, 0.62, 0.40])
        case .transcribing:
            return dots(in: rect, count: 3)
        case .recording:
            let badge = RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous)
                .path(in: rect)
            return badge.subtracting(bars(in: rect, heights: [0.34, 0.58, 0.34], widen: true))
        case .meeting:
            let badge = RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous)
                .path(in: rect)
            let d = rect.width * 0.30
            let dot = Circle().path(in: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d))
            return badge.subtracting(dot)
        }
    }

    private func bars(in rect: CGRect, heights: [Double], widen: Bool = false) -> Path {
        var path = Path()
        let barWidth = rect.width * (widen ? 0.16 : 0.15)
        let gap = rect.width * 0.12
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

    private func dots(in rect: CGRect, count: Int) -> Path {
        var path = Path()
        let d = rect.width * 0.16
        let gap = rect.width * 0.14
        let totalWidth = CGFloat(count) * d + CGFloat(count - 1) * gap
        var x = rect.midX - totalWidth / 2 + d / 2
        for _ in 0..<count {
            path.addPath(Circle().path(in: CGRect(x: x - d / 2, y: rect.midY - d / 2, width: d, height: d)))
            x += d + gap
        }
        return path
    }
}

public enum MenuBarIcon {
    /// Square, matching the footprint of a standard SF Symbol menu bar glyph.
    private static let side: CGFloat = 18

    @MainActor
    public static func image(for state: MenuBarState) -> NSImage {
        let view = MenuBarGlyph(state: state).fill(.black).frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3  // Retina-crisp; NSImage.size below fixes the logical footprint.
        let image = NSImage(size: NSSize(width: side, height: side))
        if let cg = renderer.cgImage {
            image.addRepresentation(NSBitmapImageRep(cgImage: cg))
        }
        image.isTemplate = true  // macOS re-tints for light/dark menu bars and click state.
        return image
    }
}
