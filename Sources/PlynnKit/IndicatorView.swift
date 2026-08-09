import SwiftUI

/// The floating capsule: Liquid Glass surface whose bottom third is a live
/// waveform blended into the glass, centered text that fades up and slides
/// as it overflows, and a close-in checkmark on success.
struct IndicatorView: View {
    @Bindable var model: IndicatorModel
    @Namespace private var glassNS

    private var isCompact: Bool { model.phase == .done }

    var body: some View {
        GlassEffectContainer {
            ZStack {
                // Bottom-blended visualizer — always present (inert when hidden)
                // so phase changes never reset its motion.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    BottomWave(level: model.level, idle: model.phase == .transcribing)
                        .frame(height: 26)
                }
                .opacity(waveOpacity)

                centerContent
            }
            .frame(width: isCompact ? 56 : 360, height: 52)
            .clipShape(Capsule())
            .glassEffect(.regular.tint(.black.opacity(0.18)).interactive(), in: .capsule)
            .glassEffectID("capsule", in: glassNS)
            // Explicit glass character — a bright rim light along the top edge
            // and a soft specular sheen, visible on any background.
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.5), location: 0),
                            .init(color: .white.opacity(0.06), location: 0.35),
                            .init(color: .white.opacity(0.18), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .clear],
                            startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false))
        }
        .contentShape(Capsule())
        .onTapGesture { model.onTap?() }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.phase)
        // Fixed-width center-aligned stage: the capsule collapses toward its
        // own center instead of snapping to the panel's leading edge.
        .frame(width: 360, height: 52, alignment: .center)
        .padding(4)
    }

    private var waveOpacity: Double {
        switch model.phase {
        case .recording: return 1
        // Off while polishing — the near-still wave reads as a smudge under
        // the glass rather than motion.
        case .transcribing, .done, .secure: return 0
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch model.phase {
        case .recording(let handsFree):
            HStack(spacing: 8) {
                if handsFree {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .transition(.opacity)
                }
                ScrollingPartial(text: model.partial, placeholder: "Listening…")
            }
            .padding(.horizontal, 22)
        case .transcribing:
            Text("Polishing…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .transition(.opacity)
        case .done:
            AnimatedCheckmark()
        case .secure:
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.white.opacity(0.9))
                Text("Secure field — dictation paused")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// Centered dictation text: fades up as it first appears; once it outgrows
/// the container it pins to the trailing edge, so each new word slides the
/// line left under soft gradient fades — subtle, macOS-native motion.
private struct ScrollingPartial: View {
    let text: String
    let placeholder: String
    @State private var textWidth: CGFloat = 0

    private let containerWidth: CGFloat = 296
    private var overflowing: Bool { textWidth > containerWidth }

    var body: some View {
        ZStack {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .transition(.opacity)
            } else {
                Text(text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) {
                        textWidth = $0
                    }
                    .frame(
                        width: containerWidth,
                        alignment: overflowing ? .trailing : .center)
                    .clipped()
                    .mask(
                        HStack(spacing: 0) {
                            LinearGradient(
                                colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 18)
                                .opacity(overflowing ? 1 : 0)
                            Rectangle()
                            LinearGradient(
                                colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 12)
                        })
                    .animation(.smooth(duration: 0.28), value: text)
                    .transition(.opacity.combined(with: .offset(y: 7)))
            }
        }
        .animation(.smooth(duration: 0.3), value: text.isEmpty)
    }
}

/// Filled, layered waves rising from the capsule floor — low opacity, masked
/// so they dissolve upward into the glass. Amplitude breathes with the mic.
private struct BottomWave: View {
    let level: Float
    let idle: Bool

    private struct Layer {
        let frequency: Double
        let speed: Double
        let ampScale: Double
        let baseHeight: Double
        let opacity: Double
    }

    private static let layers: [Layer] = [
        .init(frequency: 1.3, speed: 1.9, ampScale: 1.00, baseHeight: 6, opacity: 0.32),
        .init(frequency: 2.1, speed: -1.4, ampScale: 0.78, baseHeight: 5, opacity: 0.22),
        .init(frequency: 3.4, speed: 2.7, ampScale: 0.55, baseHeight: 3, opacity: 0.14),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // Typical speech RMS ~0.02–0.2 → 0…1 with a soft knee.
                let drive = idle ? 0.12 : min(1, Double(level) * 8.5)

                for (index, layer) in Self.layers.enumerated() {
                    var fill = Path()
                    var crest = Path()
                    let amp = (size.height - layer.baseHeight)
                        * layer.ampScale * (0.10 + 0.90 * drive)
                    fill.move(to: CGPoint(x: 0, y: size.height))
                    let steps = 56
                    for i in 0...steps {
                        let progress = Double(i) / Double(steps)
                        let x = size.width * progress
                        // Two incommensurate sines per layer for an organic edge.
                        let wave = sin(progress * layer.frequency * 2 * .pi + t * layer.speed)
                            * 0.7
                            + sin(progress * layer.frequency * 3.7 * .pi - t * layer.speed * 0.6)
                            * 0.3
                        let y = size.height - layer.baseHeight - max(0, wave) * amp
                        fill.addLine(to: CGPoint(x: x, y: y))
                        if i == 0 { crest.move(to: CGPoint(x: x, y: y)) }
                        else { crest.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(.white.opacity(layer.opacity)))
                    // Bright crest line on the front layer keeps the wave
                    // legible even over light backgrounds.
                    if index == 0 {
                        ctx.stroke(
                            crest, with: .color(.white.opacity(0.45)),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    }
                }
            }
        }
        // Dissolve upward into the glass; solid only at the very bottom.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.7), location: 0.55),
                    .init(color: .white, location: 1),
                ],
                startPoint: .top, endPoint: .bottom))
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

/// Check mark that draws itself on, with a small spring pop.
private struct AnimatedCheckmark: View {
    @State private var progress: CGFloat = 0
    @State private var popped = false

    var body: some View {
        CheckShape()
            .trim(from: 0, to: progress)
            .stroke(
                .white,
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .frame(width: 20, height: 20)
            .scaleEffect(popped ? 1 : 0.6)
            .opacity(popped ? 1 : 0)
            .onAppear {
                // Wait out the capsule's shrink (spring response 0.38) so the
                // check never draws against a still-moving boundary.
                withAnimation(.easeOut(duration: 0.28).delay(0.3)) { progress = 1 }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.28)) {
                    popped = true
                }
            }
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.55))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.85))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.95, y: rect.minY + rect.height * 0.18))
            return p
        }
    }
}
