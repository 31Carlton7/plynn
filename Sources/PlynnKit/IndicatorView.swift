import SwiftUI

/// Content of the floating capsule: Liquid Glass surface, white type, and a
/// fluid ribbon visualizer driven by live mic level.
struct IndicatorView: View {
    @Bindable var model: IndicatorModel
    @Namespace private var glassNS

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                switch model.phase {
                case .recording(let handsFree):
                    if handsFree {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    FluidRibbon(level: model.level, idle: false)
                        .frame(width: 74, height: 30)
                    Text(displayPartial)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(model.partial.isEmpty ? .white.opacity(0.45) : .white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                case .transcribing:
                    FluidRibbon(level: 0.04, idle: true)
                        .frame(width: 74, height: 30)
                    Text("Polishing…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .secure:
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Secure field — dictation paused")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .frame(width: 360, height: 52)
            .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: .capsule)
            .glassEffectID("capsule", in: glassNS)
        }
        .contentShape(Capsule())
        .onTapGesture { model.onTap?() }
        .animation(.smooth(duration: 0.3), value: model.phase)
        .padding(4)
    }

    private var displayPartial: String {
        if model.partial.isEmpty { return "Listening…" }
        return String(model.partial.suffix(46))
    }
}

/// Layered white sine ribbons whose amplitude breathes with the mic level.
/// Phase advances continuously via TimelineView so the motion never freezes;
/// an end-pinned envelope keeps the ribbon inside the capsule.
private struct FluidRibbon: View {
    let level: Float
    let idle: Bool

    private struct Ribbon {
        let frequency: Double   // waves across the width
        let speed: Double       // phase advance per second
        let ampScale: Double
        let opacity: Double
        let lineWidth: Double
    }

    private static let ribbons: [Ribbon] = [
        .init(frequency: 1.6, speed: 2.4, ampScale: 1.00, opacity: 0.95, lineWidth: 2.2),
        .init(frequency: 2.3, speed: -1.7, ampScale: 0.70, opacity: 0.45, lineWidth: 1.6),
        .init(frequency: 3.1, speed: 3.3, ampScale: 0.45, opacity: 0.25, lineWidth: 1.2),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // Typical speech RMS is ~0.02–0.2; map to 0…1 with a soft knee.
                let drive = idle ? 0.12 : min(1, Double(level) * 7)
                let midY = size.height / 2
                let maxAmp = (size.height / 2) - 2

                for r in Self.ribbons {
                    var path = Path()
                    let amp = maxAmp * r.ampScale * (0.12 + 0.88 * drive)
                    let steps = 48
                    for i in 0...steps {
                        let x = size.width * Double(i) / Double(steps)
                        let progress = Double(i) / Double(steps)
                        let envelope = sin(.pi * progress)  // pin both ends
                        let y = midY + sin(progress * r.frequency * 2 * .pi + t * r.speed)
                            * amp * envelope
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(
                        path,
                        with: .color(.white.opacity(r.opacity)),
                        style: StrokeStyle(lineWidth: r.lineWidth, lineCap: .round))
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
