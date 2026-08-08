import SwiftUI

/// Content of the floating capsule: waveform + live partial text while
/// recording, pulsing dots while transcribing, lock states for secure input.
struct IndicatorView: View {
    @Bindable var model: IndicatorModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .recording(let handsFree):
                if handsFree {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Waveform(level: model.level)
                Text(displayPartial)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(model.partial.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .transcribing:
                PulsingDots()
                Text("…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            case .secure:
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.red)
                Text("Secure field — dictation paused")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 40)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .contentShape(Capsule())
        .onTapGesture { model.onTap?() }
        .padding(2)
    }

    private var displayPartial: String {
        if model.partial.isEmpty { return "Listening…" }
        return String(model.partial.suffix(42))
    }
}

private struct Waveform: View {
    let level: Float
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(.tint)
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        // Center-weighted bars scaled by live RMS (typical speech RMS ~0.02–0.2).
        let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.8, 0.5]
        let normalized = min(1, CGFloat(level) * 8)
        return max(3, 22 * normalized * weights[i])
    }
}

private struct PulsingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(on ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: on)
            }
        }
        .onAppear { on = true }
    }
}
