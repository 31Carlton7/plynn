import SwiftUI
import UniformTypeIdentifiers

// Staged product shots for plynn.app: every scene is drawn inside an
// original MacBook-style device frame (bezel + notch + menu bar) so the
// media reads as "the app on a Mac" without any screen capture.

func ease(_ x: Double) -> Double { x < 0 ? 0 : x > 1 ? 1 : x * x * (3 - 2 * x) }
func spring(_ x: Double) -> Double {
    let c = ease(x)
    return x <= 0 ? 0 : x >= 1 ? 1 : c + sin(x * .pi) * 0.12 * (1 - x)
}

// MARK: - Device frame

struct MacFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.10))
            // Screen
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color(red: 0.93, green: 0.93, blue: 0.95),
                             Color(red: 0.88, green: 0.88, blue: 0.91)],
                    startPoint: .top, endPoint: .bottom)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                menuBar
                // Notch
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.09, blue: 0.10))
                    .frame(width: 168, height: 26)
                    .offset(y: -8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(13)
        }
    }

    var menuBar: some View {
        HStack(spacing: 20) {
            Image(systemName: "apple.logo").font(.system(size: 13))
            Text("Notes").fontWeight(.semibold)
            Text("File"); Text("Edit"); Text("Format"); Text("View"); Text("Window"); Text("Help")
            Spacer()
            Image(systemName: "waveform")
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            Text("Mon 9:41 AM")
        }
        .font(.system(size: 13))
        .foregroundStyle(.black.opacity(0.75))
        .padding(.horizontal, 18)
        .frame(height: 32)
        .background(.white.opacity(0.55))
    }
}

// MARK: - Pill (faithful to IndicatorView)

struct WaveLayer { let frequency, speed, ampScale, baseHeight, opacity: Double }
let waveLayers: [WaveLayer] = [
    .init(frequency: 1.3, speed: 1.4, ampScale: 1.00, baseHeight: 6, opacity: 0.30),
    .init(frequency: 2.1, speed: -1.05, ampScale: 0.82, baseHeight: 5, opacity: 0.20),
    .init(frequency: 3.4, speed: 2.0, ampScale: 0.60, baseHeight: 3, opacity: 0.13),
]

struct Wave: View {
    let t: Double
    var body: some View {
        Canvas { ctx, size in
            let drive = 0.3 + 0.35 * abs(sin(t * 2.3)) * (0.6 + 0.4 * sin(t * 5.1))
            for (i, layer) in waveLayers.enumerated() {
                var fill = Path(); var crest = Path()
                let amp = (size.height - layer.baseHeight) * layer.ampScale * (0.1 + 0.9 * drive)
                fill.move(to: CGPoint(x: 0, y: size.height))
                for s in 0...64 {
                    let p = Double(s) / 64
                    let x = size.width * p
                    let w = sin(p * layer.frequency * 2 * .pi + t * layer.speed) * 0.7
                        + sin(p * layer.frequency * 3.7 * .pi - t * layer.speed * 0.6) * 0.3
                    let y = size.height - layer.baseHeight - max(0, w) * amp
                    fill.addLine(to: CGPoint(x: x, y: y))
                    if s == 0 { crest.move(to: CGPoint(x: x, y: y)) } else { crest.addLine(to: CGPoint(x: x, y: y)) }
                }
                fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.closeSubpath()
                ctx.fill(fill, with: .color(.white.opacity(layer.opacity)))
                if i == 0 {
                    ctx.stroke(crest, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom))
    }
}

struct Pill: View {
    let t: Double
    var width: CGFloat = 360
    var text = ""
    var placeholder = false
    var waves = true
    var check: Double = 0
    var leadingIcon: String? = nil
    var iconTint: Color = .white

    var body: some View {
        ZStack {
            Capsule().fill(Color.black.opacity(0.62))
            if waves {
                VStack(spacing: 0) { Spacer(minLength: 0); Wave(t: t).frame(height: 20) }.clipShape(Capsule())
            }
            if (!text.isEmpty || placeholder) && check <= 0 {
                HStack(spacing: 8) {
                    if let icon = leadingIcon {
                        Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(iconTint)
                    }
                    Text(placeholder ? "Listening…" : text)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(placeholder ? Color.white.opacity(0.45) : .white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 22)
            }
            if check > 0 {
                CheckShape().trim(from: 0, to: check)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: width, height: 52)
        .overlay(Capsule().strokeBorder(
            LinearGradient(stops: [
                .init(color: .white.opacity(0.55), location: 0),
                .init(color: .white.opacity(0.07), location: 0.4),
                .init(color: .white.opacity(0.2), location: 1)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1.4))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.85))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.95, y: rect.minY + rect.height * 0.18))
        return p
    }
}

// MARK: - Mock windows

struct WindowChrome<Content: View>: View {
    var title: String
    var width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 1, green: 0.75, blue: 0.18)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 0.22, green: 0.79, blue: 0.26)).frame(width: 11, height: 11)
                Spacer()
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.55))
                Spacer()
                Color.clear.frame(width: 47, height: 1)
            }
            .padding(.horizontal, 14).frame(height: 38)
            .background(Color(red: 0.96, green: 0.96, blue: 0.97))
            Divider().opacity(0.5)
            content
        }
        .frame(width: width)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
    }
}

// MARK: - Scenes

let demoWords = "Tell the team the new build is ready to test".split(separator: " ").map(String.init)

struct DictationScene: View {
    let t: Double  // 0–6 looping

    var body: some View {
        let appear = spring(t / 0.5)
        let wordCount = t < 0.65 ? 0 : min(demoWords.count, Int((t - 0.65) / 0.24) + 1)
        let listening = wordCount == 0
        let speaking = t < 3.35
        let polishing = t >= 3.35 && t < 3.95
        let done = t >= 3.95
        let check = done ? ease((t - 4.15) / 0.3) : 0
        let landed = t >= 4.55
        let fadeOut = t > 5.55 ? ease((t - 5.55) / 0.45) : 0

        MacFrame {
            ZStack {
                WindowChrome(title: "Notes", width: 700) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Build 0.1.7").font(.system(size: 19, weight: .bold)).foregroundStyle(.black.opacity(0.85))
                        Text("Shipped the new menu bar icon and the calmer waveform.")
                            .font(.system(size: 14)).foregroundStyle(.black.opacity(0.55))
                        if landed {
                            Text("Tell the team the new build is ready to test.")
                                .font(.system(size: 14)).foregroundStyle(.black.opacity(0.85))
                                .opacity(ease((t - 4.55) / 0.3))
                        }
                        Spacer()
                    }
                    .padding(22)
                    .frame(height: 330, alignment: .top)
                }
                .offset(y: -80)

                Pill(
                    t: t,
                    width: done ? 56 : 460,
                    text: polishing ? "Polishing…" : demoWords.prefix(wordCount).joined(separator: " "),
                    placeholder: listening,
                    waves: speaking,
                    check: check)
                .scaleEffect(appear)
                .offset(y: 235)
                .opacity(1 - fadeOut)
            }
        }
    }
}

struct MeetingScene: View {
    var body: some View {
        MacFrame {
            ZStack {
                WindowChrome(title: "Momentum Sync — Notes", width: 660) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("# Momentum Sync — Aug 25").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(.black.opacity(0.85))
                        Text("A 22 minute call, summarized on device.").font(.system(size: 12)).foregroundStyle(.black.opacity(0.4))
                        VStack(alignment: .leading, spacing: 8) {
                            bullet("Ship the pricing page before Thursday's review")
                            bullet("Sam owns the migration script; draft lands tomorrow")
                            bullet("Beta invites go out once crash-free rate holds at 99.5%")
                        }
                        Text("## Action items").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.black.opacity(0.75)).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            bullet("Carlton: record the demo clip")
                            bullet("Maya: confirm the App Store screenshots")
                        }
                        Spacer()
                    }
                    .padding(22)
                    .frame(height: 360, alignment: .top)
                }
                .offset(y: -70)

                Pill(t: 1.2, width: 340, text: "Recording meeting · 21:47", waves: true,
                     leadingIcon: "record.circle.fill", iconTint: Color(red: 1, green: 0.3, blue: 0.28))
                    .offset(y: 245)
            }
        }
    }

    func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("-").font(.system(size: 13, design: .monospaced)).foregroundStyle(.black.opacity(0.35))
            Text(s).font(.system(size: 13, design: .monospaced)).foregroundStyle(.black.opacity(0.65))
        }
    }
}

struct CommandScene: View {
    var body: some View {
        MacFrame {
            ZStack {
                WindowChrome(title: "Mail — Re: Timeline", width: 700) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hi Priya,").font(.system(size: 14)).foregroundStyle(.black.opacity(0.8))
                        Text("I wanted to reach out and let you know that we have been making a lot of progress on the project and we think that we should be able to have everything wrapped up and delivered at some point before the end of next week.")
                            .font(.system(size: 14)).foregroundStyle(.black.opacity(0.85))
                            .padding(3)
                            .background(Color(red: 0.7, green: 0.83, blue: 1).opacity(0.75))
                            .cornerRadius(3)
                        Text("Best,\nCarlton").font(.system(size: 14)).foregroundStyle(.black.opacity(0.8))
                        Spacer()
                    }
                    .padding(22)
                    .frame(height: 300, alignment: .top)
                }
                .offset(y: -85)

                Pill(t: 0.9, width: 300, text: "\u{201C}make this shorter\u{201D}", waves: true)
                    .offset(y: 210)
            }
        }
    }
}

struct HomeScene: View {
    var body: some View {
        MacFrame {
            WindowChrome(title: "Plynn", width: 680) {
                VStack(spacing: 0) {
                    HStack(spacing: 26) {
                        tab("house", "Home", active: true)
                        tab("character.book.closed", "Dictionary", active: false)
                        tab("text.insert", "Snippets", active: false)
                        tab("gearshape", "Settings", active: false)
                    }
                    .frame(height: 44)
                    Divider().opacity(0.4)
                    HStack(spacing: 12) {
                        stat("142", "Words/min"); stat("386", "Dictations"); stat("18,204", "Words"); stat("129 min", "Time spoken")
                    }
                    .padding(18)
                    VStack(spacing: 8) {
                        row("message.fill", Color(red: 0.3, green: 0.75, blue: 0.35), "On my way, save me a seat", "Messages · just now")
                        row("envelope.fill", Color(red: 0.35, green: 0.55, blue: 0.95), "Thanks for the intro, following up with times below.", "Mail · 12 min ago")
                        row("terminal.fill", .black.opacity(0.75), "git rebase the feature branch onto main", "Ghostty · 1 hr ago")
                    }
                    .padding(.horizontal, 18).padding(.bottom, 18)
                }
            }
        }
    }

    func tab(_ icon: String, _ label: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 14))
            Text(label).font(.system(size: 10))
        }
        .foregroundStyle(active ? Color.accentColor : .black.opacity(0.45))
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(.black.opacity(0.85))
            Text(l).font(.system(size: 11)).foregroundStyle(.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 13)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    func row(_ icon: String, _ tint: Color, _ text: String, _ meta: String) -> some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 7).fill(tint).frame(width: 30, height: 30)
                .overlay(Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 13)).foregroundStyle(.black.opacity(0.85)).lineLimit(1)
                Text(meta).font(.system(size: 11)).foregroundStyle(.black.opacity(0.4))
            }
            Spacer()
            Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(.black.opacity(0.35))
        }
        .padding(10)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Render

let W: CGFloat = 1440, H: CGFloat = 900

@MainActor
func write(_ view: some View, to url: URL) {
    let r = ImageRenderer(content: view.frame(width: W, height: H).environment(\.colorScheme, .light))
    r.scale = 1.5
    guard let cg = r.cgImage,
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("render failed") }
    CGImageDestinationAddImage(d, cg, nil)
    CGImageDestinationFinalize(d)
}

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 2 ? args[2] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    switch args.count > 1 ? args[1] : "all" {
    case "dictation":
        let fps = 12.0, dur = 6.0
        for i in 0..<Int(fps * dur) {
            write(DictationScene(t: Double(i) / fps), to: out.appendingPathComponent(String(format: "d_%03d.png", i)))
        }
        print("dictation frames done")
    case "og":
        let r = ImageRenderer(content: OGCard().frame(width: 1200, height: 630).environment(\.colorScheme, .light))
        r.scale = 2
        if let cg = r.cgImage,
            let d = CGImageDestinationCreateWithURL(out.appendingPathComponent("og.png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(d, cg, nil); CGImageDestinationFinalize(d)
        }
        print("og done")
    case "statics":
        write(MeetingScene(), to: out.appendingPathComponent("meeting.png"))
        write(CommandScene(), to: out.appendingPathComponent("command.png"))
        write(HomeScene(), to: out.appendingPathComponent("home.png"))
        print("statics done")
    default: fatalError("scene?")
    }
}

// 1200×630 social share card: site headline + the pill, brand-clean.
struct OGCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [.white, Color(red: 0.955, green: 0.955, blue: 0.965)],
                startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(red: 0.12, green: 0.13, blue: 0.17))
                        .frame(width: 34, height: 34)
                        .overlay(Capsule().fill(.white.opacity(0.85)).frame(width: 18, height: 8))
                    Text("Plynn").font(.system(size: 22, weight: .medium)).foregroundStyle(.black.opacity(0.6))
                }
                Spacer()
                Text("Dictation that never\ntouches the internet.")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.9))
                    .lineSpacing(2)
                Spacer()
                HStack {
                    Pill(t: 1.1, width: 470, text: "Tell the team the build is ready", waves: true)
                        .scaleEffect(0.9, anchor: .leading)
                    Spacer()
                    Text("plynn.app")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Color(red: 0.12, green: 0.12, blue: 0.12), in: Capsule())
                }
            }
            .padding(56)
        }
    }
}
