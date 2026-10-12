import SwiftUI
import UniformTypeIdentifiers

// Draws Plynn's app icon and every size derived from it.
//
//   swift scripts/make-icon.swift
//
// Writes scripts/AppIcon.icns, the site's icon, favicons and touch icon, and
// docs/assets/icon.png. The mark is the menu bar glyph's three bars, drawn as
// glass over the same dusk gradient the site uses.

let canvas: CGFloat = 1024
let body: CGFloat = 824          // macOS icon grid: 824 pt body, 100 pt margin
let corner: CGFloat = 185

func hex(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
          blue: Double(v & 0xff) / 255, opacity: a)
}

/// The square artwork, edge to edge. `simple` drops the fine detail that turns
/// to mud below 64 px and fattens the bars so they survive at 16 px.
struct Artwork: View {
    var simple = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [hex(0x232A52), hex(0x11132C), hex(0x090A14)],
                           startPoint: .top, endPoint: .bottom)
            dusk
            bars
        }
        .frame(width: 824, height: 824)
    }

    private var dusk: some View {
        ZStack {
            Ellipse().fill(hex(0x2F45C8, 0.5)).frame(width: 840, height: 460).offset(x: 208, y: -390)
            Ellipse().fill(hex(0xFF7A45, 0.95)).frame(width: 660, height: 420).offset(x: -282, y: 478)
            Ellipse().fill(hex(0xE2487A, 0.9)).frame(width: 560, height: 340).offset(x: 48, y: 498)
            Ellipse().fill(hex(0x8A4CE6, 0.95)).frame(width: 540, height: 460).offset(x: 388, y: 388)
        }
        .blur(radius: simple ? 60 : 80)
        .opacity(simple ? 0.75 : 1)
    }

    private var bars: some View {
        let width: CGFloat = simple ? 164 : 132
        let gap: CGFloat = simple ? 58 : 68
        let heights: [CGFloat] = simple ? [300, 470, 300] : [252, 404, 252]
        let shape = Bars(width: width, gap: gap, heights: heights)
        return ZStack {
            // Light the bars throw onto the glass below them.
            shape.fill(hex(0xB9A8FF, 0.55)).blur(radius: 40).offset(y: 40)
            shape.fill(.black.opacity(0.35)).blur(radius: 12).offset(y: 18)
            shape.fill(LinearGradient(
                stops: [.init(color: .white, location: 0),
                        .init(color: hex(0xEDEBFF), location: 0.55),
                        .init(color: hex(0xC9C2FF), location: 1)],
                startPoint: .top, endPoint: .bottom))
            if !simple {
                // Specular streak down the left of each bar, like light on a glass rod.
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(0), location: 0.05),
                            .init(color: .white.opacity(0.9), location: 0.22),
                            .init(color: .white.opacity(0), location: 0.4)],
                    startPoint: .leading, endPoint: .trailing))
                    .mask(shape.fill(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)))
                    .opacity(0.5)
                shape.stroke(.white.opacity(0.9), lineWidth: 2)
            }
        }
        .offset(y: -12)  // optical center: the bars read low when truly centered
    }
}

/// Three capsule bars centered in their rect, the menu bar glyph at icon scale.
struct Bars: Shape {
    let width: CGFloat, gap: CGFloat, heights: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
        var x = rect.midX - total / 2
        for h in heights {
            path.addPath(Capsule().path(in: CGRect(x: x, y: rect.midY - h / 2, width: width, height: h)))
            x += width + gap
        }
        return path
    }
}

/// The macOS icon: artwork in a continuous-corner squircle on the 1024 grid,
/// with a top rim light and the standard soft drop shadow.
struct AppIcon: View {
    var simple = false

    var body: some View {
        let squircle = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Artwork(simple: simple)
            .clipShape(squircle)
            .overlay(squircle.strokeBorder(LinearGradient(
                stops: [.init(color: .white.opacity(0.3), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.25),
                        .init(color: .white.opacity(0.12), location: 1)],
                startPoint: .top, endPoint: .bottom), lineWidth: 3))
            .shadow(color: .black.opacity(0.38), radius: 16, y: 14)
            .frame(width: canvas, height: canvas)
    }
}

// MARK: - Output

@MainActor
func render(_ view: some View, side: CGFloat, px: Int) -> CGImage {
    let r = ImageRenderer(content: view.frame(width: side, height: side))
    r.scale = CGFloat(px) / side
    guard let cg = r.cgImage else { fatalError("render failed") }
    return cg
}

func png(_ image: CGImage) -> Data {
    let data = NSMutableData()
    guard let d = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("png encoder") }
    CGImageDestinationAddImage(d, image, nil)
    CGImageDestinationFinalize(d)
    return data as Data
}

func write(_ image: CGImage, to path: String) {
    try! png(image).write(to: URL(fileURLWithPath: path))
}

/// A .ico holding PNG frames, which every browser since IE 11 reads.
func ico(_ images: [CGImage]) -> Data {
    var out = Data()
    func u16(_ v: Int) { out.append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8)]) }
    func u32(_ v: Int) { u16(v & 0xffff); u16(v >> 16) }
    let frames = images.map(png)
    u16(0); u16(1); u16(images.count)
    var offset = 6 + 16 * images.count
    for (image, frame) in zip(images, frames) {
        out.append(UInt8(image.width % 256)); out.append(UInt8(image.height % 256))
        out.append(0); out.append(0); u16(1); u16(32)
        u32(frame.count); u32(offset)
        offset += frame.count
    }
    frames.forEach { out.append($0) }
    return out
}

MainActor.assumeIsolated {
    let fm = FileManager.default
    let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
    try? fm.removeItem(atPath: iconset)
    try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = pt * scale
            let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
            write(render(AppIcon(simple: px < 64), side: canvas, px: px), to: "\(iconset)/\(name)")
        }
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset, "-o", "scripts/AppIcon.icns"]
    try! iconutil.run(); iconutil.waitUntilExit()

    let full = render(AppIcon(), side: canvas, px: 1024)
    write(full, to: "site/assets/icon.png")
    write(full, to: "docs/assets/icon.png")

    // Browsers show favicons and touch icons edge to edge, so these skip the
    // icon grid's margin and shadow. iOS rounds the touch icon itself.
    let tab = RoundedRectangle(cornerRadius: 190, style: .continuous)
    let favicon = { (px: Int) in render(Artwork(simple: true).clipShape(tab), side: body, px: px) }
    write(favicon(16), to: "site/assets/favicon-16.png")
    write(favicon(32), to: "site/assets/favicon-32.png")
    try! ico([favicon(16), favicon(32), favicon(48)]).write(to: URL(fileURLWithPath: "site/favicon.ico"))
    write(render(Artwork(), side: body, px: 180), to: "site/assets/apple-touch-icon.png")
    print("icons written")
}
