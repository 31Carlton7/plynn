import SwiftUI

/// Capsule geometry in one place — every size below derives from these, so
/// resizing the pill is a one-line change rather than a hunt through the view.
enum IndicatorMetrics {
    static let width: CGFloat = 168
    static let height: CGFloat = 34
    /// Collapsed width for the success check mark.
    static let compactWidth: CGFloat = 36
    /// Height of the waveform band at the capsule floor. Tall relative to the
    /// capsule on purpose — the upward-dissolve mask keeps the crests from
    /// fighting the transcript that sits over them.
    static let waveHeight: CGFloat = 24
    static let textSize: CGFloat = 11
    /// Scrolling-transcript viewport; the rest is breathing room.
    static let textWidth: CGFloat = 122
    static let inset: CGFloat = 12
    /// Slack around the capsule inside the panel, for the glass shadow.
    static let panelPadding: CGFloat = 4
    /// Gap from the bottom of the usable screen (above the Dock) to the
    /// capsule. Low enough to sit out of the way, clear enough not to look
    /// like it's falling off the edge.
    static let bottomMargin: CGFloat = 14
}

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
                // TimelineView is removed while the panel is hidden or
                // polishing. Opacity alone would leave its Canvas ticking.
                if showsWave {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        BottomWave(level: model.level)
                            .frame(height: IndicatorMetrics.waveHeight)
                    }
                }

                // A plain crossfade showed both phases' text over each other.
                centerContent
                    .transition(.blurReplace)
            }
            .frame(
                width: isCompact ? IndicatorMetrics.compactWidth : IndicatorMetrics.width,
                height: IndicatorMetrics.height)
            .clipShape(Capsule())
            // Clear glass under a dark tint: smoked glass with the backdrop
            // still showing through. Regular glass turns light grey over a
            // white page, which leaves the white text and wave with no contrast.
            .glassEffect(.clear.tint(.black.opacity(0.55)).interactive(), in: .capsule)
            .glassEffectID("capsule", in: glassNS)
            // A hairline so the edge still reads over a dark window.
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        }
        .contentShape(Capsule())
        .onTapGesture { model.onTap?() }
        // Only morph between phases on screen. A fresh show starts in its new
        // phase instead of unfolding from the check mark it was hidden on.
        .animation(
            model.isPresented ? .spring(response: 0.38, dampingFraction: 0.82) : nil,
            value: model.phase)
        .scaleEffect(model.isPresented ? 1 : 0.9, anchor: .bottom)
        .offset(y: model.isPresented ? 0 : 6)
        .opacity(model.isPresented ? 1 : 0)
        .animation(
            model.isPresented
                ? .spring(response: 0.36, dampingFraction: 0.72)
                : .easeIn(duration: IndicatorPanel.exitDuration),
            value: model.isPresented)
        // Fixed-width center-aligned stage: the capsule collapses toward its
        // own center instead of snapping to the panel's leading edge.
        .frame(
            width: IndicatorMetrics.width, height: IndicatorMetrics.height,
            alignment: .center)
        .padding(IndicatorMetrics.panelPadding)
    }

    private var showsWave: Bool {
        guard model.isVisible else { return false }
        switch model.phase {
        case .recording, .meeting: return true
        case .transcribing, .done, .secure, .micUnavailable, .error, .meetingSaved:
            return false
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch model.phase {
        case .recording(let handsFree):
            HStack(spacing: 6) {
                if handsFree {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .transition(.opacity)
                }
                ScrollingPartial(text: model.partial, placeholder: "Listening…")
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        case .transcribing:
            PolishingLabel()
        case .done:
            AnimatedCheckmark()
        case .secure:
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.white.opacity(0.9))
                Text("Secure field — dictation paused")
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        case .micUnavailable:
            HStack(spacing: 6) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.white.opacity(0.9))
                Text("Microphone unavailable")
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        case .error(let message):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow.opacity(0.95))
                    Text(message)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if !model.partial.isEmpty {
                    ScrollingPartial(text: model.partial, placeholder: "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
        case .meeting(let elapsed):
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .modifier(RecordingPulse())
                Text("Recording meeting")
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(Self.clock(elapsed))
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        case .meetingSaved:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Meeting saved — writing notes…")
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        }
    }
}

/// The polish stage is the app quietly working on your words — a soft light
/// sweeps once through "Polishing…", brightening each glyph a touch as it
/// passes, then settles. Monochrome and understated on purpose: the earlier
/// version lifted glyphs, cycled their hue, and threw sparkles off a glowing
/// head, which read as gaudy rather than calm. This keeps the same idea (text
/// being worked on, not a generic loading spinner) at a fraction of the
/// amplitude. Driven purely by the wall clock, so there is no state to leak.
struct PolishingLabel: View {
    private static let word = Array("Polishing…")
    /// Seconds per pass — slow and even, nothing to catch the eye.
    private static let period: Double = 2.6
    /// Wide spread means the brightening is a gentle glow, not a hot spot.
    private static let spread: Double = 3.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let count = Double(Self.word.count)
            let phase = (time.truncatingRemainder(dividingBy: Self.period)) / Self.period
            // Runs from fully before the first glyph to fully past the last,
            // so nothing pops at the wrap.
            let head = -3.0 + phase * (count + 6)

            HStack(spacing: 0) {
                ForEach(Array(Self.word.enumerated()), id: \.offset) { index, character in
                    let distance = (Double(index) - head) / Self.spread
                    let heat = max(0, exp(-distance * distance))

                    Text(String(character))
                        .font(
                            .system(
                                size: IndicatorMetrics.textSize, weight: .medium,
                                design: .rounded)
                        )
                        .foregroundStyle(.white.opacity(0.45 + 0.35 * heat))
                }
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

    private let containerWidth: CGFloat = IndicatorMetrics.textWidth
    private var overflowing: Bool { textWidth > containerWidth }

    var body: some View {
        ZStack {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .transition(.opacity)
            } else {
                Text(text)
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    // The default crossfade drew the old line and the new one
                    // over each other; swap in place and let the position animate.
                    .contentTransition(.identity)
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
                                .frame(width: 12)
                                .opacity(overflowing ? 1 : 0)
                            Rectangle()
                            LinearGradient(
                                colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 8)
                        })
                    .animation(.smooth(duration: 0.28), value: text)
                    .transition(.opacity.combined(with: .offset(y: 7)))
            }
        }
        .animation(.smooth(duration: 0.3), value: text.isEmpty)
    }
}

/// Filled, layered waves rising from the capsule floor — low opacity, masked
/// so they dissolve upward into the glass.
///
/// The texture comes from `max(0, wave)`: clamping the trough half of each
/// sine leaves crests scalloping up off a flat baseline rather than a
/// continuous ripple, and layers at non-harmonic frequencies overlap into
/// translucent hills that never repeat.
///
/// Every layer springs toward the current loudness, the front one fastest, so
/// the hills swell together when you start talking and settle back in depth
/// order when you stop.
private struct BottomWave: View {
    /// Smoothed loudness, 0…1.
    let level: Float
    @State private var motion = WaveMotion()

    struct Layer {
        let frequency: Double
        let speed: Double
        let ampScale: Double
        let baseHeight: Double
        let opacity: Double
        /// Spring stiffness, as natural frequency in rad/s, while the voice
        /// rises and while it falls. Falling is slower so the hills ease down
        /// between words instead of collapsing.
        let attack: Double
        let release: Double
    }

    /// Frequencies are deliberately non-harmonic — harmonically related ones
    /// line their crests up into a visibly repeating pattern.
    static let layers: [Layer] = [
        .init(frequency: 1.3, speed: 1.4, ampScale: 1.00, baseHeight: 1.6, opacity: 0.34,
              attack: 60, release: 28),
        .init(frequency: 2.1, speed: -1.05, ampScale: 0.80, baseHeight: 1.2, opacity: 0.24,
              attack: 48, release: 23),
        .init(frequency: 3.4, speed: 2.0, ampScale: 0.58, baseHeight: 0.8, opacity: 0.17,
              attack: 38, release: 19),
        .init(frequency: 5.3, speed: -2.7, ampScale: 0.38, baseHeight: 0.5, opacity: 0.11,
              attack: 30, release: 15),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let states = motion.advance(to: timeline.date, level: Double(level))
            Canvas { ctx, size in
                // Back to front, so the front hill and its crest sit on top.
                for (index, (layer, state)) in zip(Self.layers, states).enumerated().reversed() {
                    let heights = Self.heights(of: layer, state, maxHeight: size.height)
                    let step = size.width / Double(heights.count - 1)
                    var fill = Path()
                    fill.move(to: CGPoint(x: 0, y: size.height))
                    for (i, h) in heights.enumerated() {
                        fill.addLine(to: CGPoint(x: Double(i) * step, y: size.height - h))
                    }
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(.white.opacity(layer.opacity)))

                    guard index == 0 else { continue }
                    // Bright crest on the front hill keeps the wave legible over
                    // any backdrop. Only over the raised parts: run along the
                    // flat floor too and it reads as a white rule under the pill.
                    var crest = Path()
                    var drawing = false
                    for (i, h) in heights.enumerated() {
                        let point = CGPoint(x: Double(i) * step, y: size.height - h)
                        if h - layer.baseHeight > 0.4 {
                            if drawing { crest.addLine(to: point) } else { crest.move(to: point) }
                            drawing = true
                        } else {
                            drawing = false
                        }
                    }
                    ctx.stroke(
                        crest,
                        with: .color(.white.opacity(0.4 + 0.3 * state.amplitude)),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
            }
        }
        // Dissolve upward into the glass; solid only at the very bottom.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.85), location: 0.45),
                    .init(color: .white, location: 1),
                ],
                startPoint: .top, endPoint: .bottom))
    }

    /// Height of one layer above the capsule floor, sampled across the width.
    private static func heights(
        of layer: Layer, _ state: WaveMotion.State, maxHeight: Double
    ) -> [Double] {
        // Never fully flat, so the surface still lives in silence.
        let drive = 0.1 + 0.9 * max(0, state.amplitude)
        let amp = (maxHeight - layer.baseHeight) * layer.ampScale * drive
        let steps = 120
        return (0...steps).map { i in
            let progress = Double(i) / Double(steps)
            // Taper into the capsule's rounded ends rather than being cut by them.
            let edge = min(progress, 1 - progress)
            let taper = edge < 0.16 ? sin(edge / 0.16 * .pi / 2) : 1
            let phaseA = progress * layer.frequency * 2 * .pi + state.phase
            let phaseB = progress * layer.frequency * 3.7 * .pi - state.phase * 0.6
            let wave = sin(phaseA) * 0.7 + sin(phaseB) * 0.3
            return layer.baseHeight + max(0, wave) * amp * taper
        }
    }
}

/// The wave's running state, stepped once per frame. Phase is integrated
/// rather than computed as `time × speed`: with time counted in seconds since
/// 2001, any change in speed would jump every layer to an unrelated phase.
@MainActor
private final class WaveMotion {
    struct State {
        var amplitude = 0.0
        var velocity = 0.0
        var phase = 0.0
    }

    private var states = [State](repeating: State(), count: BottomWave.layers.count)
    private var lastFrame: Date?

    func advance(to now: Date, level: Double) -> [State] {
        // A frame after a stall (panel just shown, app busy) steps as one
        // normal frame instead of flinging the springs.
        let dt = min(max(now.timeIntervalSince(lastFrame ?? now), 0), 1.0 / 30)
        lastFrame = now
        for (i, layer) in BottomWave.layers.enumerated() {
            var s = states[i]
            // Below 0.2 is room noise and breath, and ordinary speech peaks
            // around 0.75. Stretching that span over the full height makes the
            // hills follow the voice instead of idling half-raised.
            let target = min(max((level - 0.2) / 0.55, 0), 1)
            let omega = target > s.amplitude ? layer.attack : layer.release
            // Underdamped, so each swell overshoots a touch before it settles.
            let acceleration = omega * omega * (target - s.amplitude) - 2 * 0.62 * omega * s.velocity
            s.velocity += acceleration * dt
            s.amplitude += s.velocity * dt
            // Ripples run a little faster while you are actually talking.
            s.phase += layer.speed * (1 + 0.9 * max(0, s.amplitude)) * dt
            states[i] = s
        }
        return states
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
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 13, height: 13)
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

extension IndicatorView {
    /// mm:ss, or h:mm:ss past an hour.
    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Slow breathing on the recording dot — reads as "live" without shouting.
private struct RecordingPulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
