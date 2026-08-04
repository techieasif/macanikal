// Renders the Macanikal launch video frames + static launch assets.
// Usage: swift tools/launch_kit.swift <framesDir> <assetsDir>
// Video: 1920x1080 @ 30 fps, 14.5 s. Audio is mixed separately by ffmpeg.
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: launch_kit.swift <framesDir> <assetsDir> [assets-only]") }
let assetsOnly = args.count > 3 && args[3] == "assets-only"
let framesDir = URL(fileURLWithPath: args[1])
let assetsDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

// MARK: - palette

let bgColor = NSColor(srgbRed: 0.020, green: 0.024, blue: 0.047, alpha: 1)
let textColor = NSColor(srgbRed: 0.933, green: 0.945, blue: 0.980, alpha: 1)
let mutedColor = NSColor(srgbRed: 0.604, green: 0.639, blue: 0.741, alpha: 1)
let accent = NSColor(srgbRed: 0.310, green: 0.486, blue: 1.0, alpha: 1)      // #4f7cff
let accentDark = NSColor(srgbRed: 0.169, green: 0.337, blue: 0.910, alpha: 1) // #2b56e8
let capTop = NSColor(srgbRed: 0.169, green: 0.184, blue: 0.239, alpha: 1)     // #2b2f3d
let capBottom = NSColor(srgbRed: 0.098, green: 0.110, blue: 0.149, alpha: 1)  // #191c26

// MARK: - helpers

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func savePNG(_ ctx: CGContext, to url: URL) {
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - min(max(t, 0), 1), 3) }
func clamp01(_ t: CGFloat) -> CGFloat { min(max(t, 0), 1) }

/// Alpha ramp: fade in over `fadeIn` starting at `start`, fade out over `fadeOut` ending at `end`.
func window(_ t: CGFloat, _ start: CGFloat, _ end: CGFloat, fadeIn: CGFloat = 0.4, fadeOut: CGFloat = 0.4) -> CGFloat {
    if t < start || t > end { return 0 }
    return min(easeOut((t - start) / fadeIn), easeOut((end - t) / fadeOut), 1)
}

func drawAurora(_ ctx: CGContext, w: CGFloat, h: CGFloat) {
    ctx.setFillColor(bgColor.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let glows: [(CGPoint, CGFloat, NSColor, CGFloat)] = [
        (CGPoint(x: w * 0.18, y: h * 0.96), w * 0.55, accentDark, 0.30),
        (CGPoint(x: w * 0.88, y: h * 0.86), w * 0.42, NSColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 1), 0.24),
        (CGPoint(x: w * 0.48, y: h * 0.42), w * 0.48, NSColor(srgbRed: 0.114, green: 0.247, blue: 0.682, alpha: 1), 0.16),
    ]
    for (center, radius, color, alpha) in glows {
        let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
        ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}

func measureText(_ string: String, size: CGFloat, weight: NSFont.Weight, mono: Bool = false) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
    return CTLineGetBoundsWithOptions(line, .useOpticalBounds).width
}

func drawText(_ ctx: CGContext, _ string: String, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, center: CGPoint, alpha: CGFloat, mono: Bool = false,
              glow: NSColor? = nil, tracking: CGFloat = 0) {
    guard alpha > 0.01 else { return }
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.withAlphaComponent(alpha)]
    if tracking != 0 { attrs[.kern] = tracking }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.saveGState()
    if let glow { ctx.setShadow(offset: .zero, blur: size * 0.5, color: glow.withAlphaComponent(alpha * 0.65).cgColor) }
    ctx.textPosition = CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// A keycap. press: 0 = at rest, 1 = fully bottomed out.
func drawKeycap(_ ctx: CGContext, center: CGPoint, size: CGFloat, letter: String,
                press: CGFloat, isAccent: Bool, alpha: CGFloat) {
    guard alpha > 0.01 else { return }
    let travel = size * 0.055 * press
    let capRect = CGRect(x: center.x - size / 2, y: center.y - size / 2 - travel, width: size, height: size)
    let radius = size * 0.18
    ctx.saveGState()
    ctx.setAlpha(alpha)

    // base plate (what the cap sinks toward)
    let plate = CGPath(roundedRect: capRect.offsetBy(dx: 0, dy: -size * 0.07 + travel), cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(plate)
    ctx.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
    ctx.fillPath()

    // cap body
    if isAccent || press > 0.02 {
        let glowColor = accent.withAlphaComponent(0.55 * max(isAccent ? 1 : 0, press))
        ctx.setShadow(offset: .zero, blur: size * 0.35, color: glowColor.cgColor)
    }
    let capPath = CGPath(roundedRect: capRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(capPath)
    ctx.clip()
    let (top, bottom) = isAccent || press > 0.5 ? (accent, accentDark) : (capTop, capBottom)
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: capRect.midX, y: capRect.maxY),
                           end: CGPoint(x: capRect.midX, y: capRect.minY), options: [])
    // inner top surface
    let inner = capRect.insetBy(dx: size * 0.09, dy: size * 0.09).offsetBy(dx: 0, dy: size * 0.045)
    ctx.addPath(CGPath(roundedRect: inner, cornerWidth: radius * 0.6, cornerHeight: radius * 0.6, transform: nil))
    ctx.setFillColor((isAccent || press > 0.5 ? accentDark.blended(withFraction: 0.25, of: .white)! : capTop.blended(withFraction: 0.35, of: capBottom)!).withAlphaComponent(0.9).cgColor)
    ctx.fillPath()
    ctx.resetClip()

    drawText(ctx, letter, size: size * 0.42, weight: .heavy, color: .white,
             center: CGPoint(x: capRect.midX, y: capRect.midY + size * 0.03), alpha: 1, mono: true)
    ctx.restoreGState()
}

func drawWordmark(_ ctx: CGContext, word: String, accentIndex: Int, center: CGPoint,
                  capSize: CGFloat, t: CGFloat, letterTimes: [CGFloat], alpha: CGFloat) {
    let gap = capSize * 0.13
    let total = CGFloat(word.count) * capSize + CGFloat(word.count - 1) * gap
    var x = center.x - total / 2 + capSize / 2
    for (i, ch) in word.enumerated() {
        let born = letterTimes[i]
        if t >= born {
            let age = t - born
            let press = age < 0.16 ? 1 - easeOut(age / 0.16) : 0
            drawKeycap(ctx, center: CGPoint(x: x, y: center.y), size: capSize, letter: String(ch),
                       press: press, isAccent: i == accentIndex, alpha: alpha)
        }
        x += capSize + gap
    }
}

// MARK: - video timeline

let W: CGFloat = 1920, H: CGFloat = 1080
let fps = 30
let duration: CGFloat = 14.5
let letterTimes: [CGFloat] = (0..<9).map { 0.6 + 0.38 * CGFloat($0) }   // MACANIKAL
let word = "MACANIKAL"

func renderFrame(_ ctx: CGContext, t: CGFloat) {
    drawAurora(ctx, w: W, h: H)

    // Scene A+B: wordmark, then it rises as the headline arrives
    let rise = easeOut(clamp01((t - 4.6) / 0.8))
    let sceneABAlpha = window(t, 0, 8.0, fadeIn: 0.01, fadeOut: 0.5)
    if sceneABAlpha > 0 {
        let capSize = 150 - 42 * rise
        let y = H * 0.5 + (H * 0.30 - H * 0.5) * rise  // 0.5H -> 0.30H from bottom? no: rises toward top
        let yPos = H * 0.52 + (H * 0.74 - H * 0.52) * rise
        _ = y
        drawWordmark(ctx, word: word, accentIndex: 3, center: CGPoint(x: W / 2, y: yPos),
                     capSize: capSize, t: t, letterTimes: letterTimes, alpha: sceneABAlpha)

        let h1a = window(t, 5.0, 8.0, fadeIn: 0.5, fadeOut: 0.5)
        let slide = (1 - easeOut(clamp01((t - 5.0) / 0.5))) * 30
        drawText(ctx, "Your keyboard,", size: 108, weight: .bold, color: textColor,
                 center: CGPoint(x: W / 2, y: H * 0.47 - slide), alpha: h1a)
        let h2a = window(t, 5.45, 8.0, fadeIn: 0.5, fadeOut: 0.5)
        let slide2 = (1 - easeOut(clamp01((t - 5.45) / 0.5))) * 30
        // "but it goes" + glowing "thock."
        drawText(ctx, "but it goes", size: 108, weight: .bold, color: textColor,
                 center: CGPoint(x: W / 2 - 170, y: H * 0.345 - slide2), alpha: h2a)
        drawText(ctx, "thock.", size: 108, weight: .heavy, color: accent,
                 center: CGPoint(x: W / 2 + 305, y: H * 0.345 - slide2), alpha: h2a, glow: accent)
        let suba = window(t, 6.1, 8.0, fadeIn: 0.5, fadeOut: 0.5)
        drawText(ctx, "Real mechanical switch sounds for your Mac", size: 44, weight: .medium,
                 color: mutedColor, center: CGPoint(x: W / 2, y: H * 0.22), alpha: suba)
    }

    // Scene C: features
    let features: [(CGFloat, String)] = [
        (8.35, "🎧  13 real switch packs"),
        (9.25, "⚡  single-digit-millisecond latency"),
        (10.15, "🔓  free & open source"),
    ]
    for (i, f) in features.enumerated() {
        let a = window(t, f.0, 11.2, fadeIn: 0.35, fadeOut: 0.45)
        let slide = (1 - easeOut(clamp01((t - f.0) / 0.35))) * 40
        drawText(ctx, f.1, size: 64, weight: .semibold, color: textColor,
                 center: CGPoint(x: W / 2, y: H * (0.62 - 0.14 * CGFloat(i)) - slide), alpha: a)
    }

    // Scene D: CTA
    let d = window(t, 11.5, 14.5, fadeIn: 0.5, fadeOut: 0.6)
    if d > 0 {
        drawKeycap(ctx, center: CGPoint(x: W / 2, y: H * 0.62), size: 190, letter: "M",
                   press: t > 11.9 && t < 12.1 ? 1 - easeOut((t - 11.9) / 0.2) : 0, isAccent: true, alpha: d)
        drawText(ctx, "Macanikal", size: 92, weight: .bold, color: textColor,
                 center: CGPoint(x: W / 2, y: H * 0.42), alpha: d)
        drawText(ctx, "github.com/techieasif/macanikal", size: 46, weight: .semibold, color: accent,
                 center: CGPoint(x: W / 2, y: H * 0.29), alpha: d, mono: true, glow: accent)
        drawText(ctx, "🔊 try it in your browser — techieasif.github.io/macanikal", size: 34, weight: .medium,
                 color: mutedColor, center: CGPoint(x: W / 2, y: H * 0.19), alpha: d)
    }
}

// MARK: - static assets

func renderLogo(square: Int, transparent: Bool, url: URL) {
    let ctx = makeContext(square, square)
    let s = CGFloat(square)
    if !transparent {
        drawAurora(ctx, w: s, h: s)
    }
    drawKeycap(ctx, center: CGPoint(x: s / 2, y: s / 2), size: s * 0.62, letter: "M",
               press: 0, isAccent: true, alpha: 1)
    savePNG(ctx, to: url)
}

func renderBanner(w: Int, h: Int, url: URL) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    drawAurora(ctx, w: W, h: H)
    let capSize = W * 0.062
    drawWordmark(ctx, word: word, accentIndex: 3, center: CGPoint(x: W / 2, y: H * 0.66),
                 capSize: capSize, t: 100, letterTimes: letterTimes, alpha: 1)
    let size1 = W * 0.030
    let seg1 = "Your keyboard, but it goes"
    let gap = size1 * 0.30
    let w1 = measureText(seg1, size: size1, weight: .bold)
    let w2 = measureText("thock.", size: size1, weight: .heavy)
    let startX = W / 2 - (w1 + gap + w2) / 2
    drawText(ctx, seg1, size: size1, weight: .bold, color: textColor,
             center: CGPoint(x: startX + w1 / 2, y: H * 0.40), alpha: 1)
    drawText(ctx, "thock.", size: size1, weight: .heavy, color: accent,
             center: CGPoint(x: startX + w1 + gap + w2 / 2, y: H * 0.40), alpha: 1, glow: accent)
    drawText(ctx, "Real mechanical switch sounds for your Mac · free & open source", size: W * 0.0165,
             weight: .medium, color: mutedColor, center: CGPoint(x: W / 2, y: H * 0.27), alpha: 1)
    drawText(ctx, "github.com/techieasif/macanikal", size: W * 0.016, weight: .semibold, color: accent,
             center: CGPoint(x: W / 2, y: H * 0.15), alpha: 1, mono: true)
    savePNG(ctx, to: url)
}

// MARK: - run

renderLogo(square: 1024, transparent: false, url: assetsDir.appendingPathComponent("logo.png"))
renderLogo(square: 1024, transparent: true, url: assetsDir.appendingPathComponent("logo-transparent.png"))
renderBanner(w: 1280, h: 640, url: assetsDir.appendingPathComponent("og-banner.png"))
renderBanner(w: 1600, h: 900, url: assetsDir.appendingPathComponent("x-card.png"))
print("assets done")

if assetsOnly { exit(0) }
let totalFrames = Int(duration * CGFloat(fps))
for f in 0..<totalFrames {
    let ctx = makeContext(Int(W), Int(H))
    renderFrame(ctx, t: CGFloat(f) / CGFloat(fps))
    savePNG(ctx, to: framesDir.appendingPathComponent(String(format: "%04d.png", f)))
    if f % 60 == 0 { print("frame \(f)/\(totalFrames)") }
}
print("frames done")
