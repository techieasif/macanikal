// Renders the Macanikal launch video frames, social assets, and app icon
// in the cartoon brand: Thocky the keycap mascot + the switch squad on a
// flat near-black dot grid (matches the website).
//
// Usage: swift tools/launch_kit.swift <framesDir> <assetsDir> [assets-only|icon-only]
// Video: 1920x1080 @ 30 fps, 15.0 s. Audio is mixed separately by ffmpeg.
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: launch_kit.swift <framesDir> <assetsDir> [assets-only|icon-only]") }
let framesDir = URL(fileURLWithPath: args[1])
let assetsDir = URL(fileURLWithPath: args[2])
let mode = args.count > 3 ? args[3] : "all"
try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

// MARK: - palette (matches docs/index.html)

let bgColor = NSColor(srgbRed: 0.039, green: 0.039, blue: 0.047, alpha: 1)   // #0a0a0c
let textColor = NSColor(srgbRed: 0.949, green: 0.949, blue: 0.957, alpha: 1) // #f2f2f4
let mutedColor = NSColor(srgbRed: 0.639, green: 0.639, blue: 0.675, alpha: 1)// #a3a3ac
let accent = NSColor(srgbRed: 0.310, green: 0.486, blue: 1.0, alpha: 1)      // #4f7cff
let accentDark = NSColor(srgbRed: 0.169, green: 0.337, blue: 0.910, alpha: 1)// #2b56e8
let ink = NSColor(srgbRed: 0.043, green: 0.063, blue: 0.188, alpha: 1)       // #0b1030
let sun = NSColor(srgbRed: 1.0, green: 0.820, blue: 0.400, alpha: 1)         // #ffd166
let pinkBlush = NSColor(srgbRed: 1.0, green: 0.561, blue: 0.671, alpha: 1)   // #ff8fab
let capTop = NSColor(srgbRed: 0.176, green: 0.176, blue: 0.200, alpha: 1)    // #2d2d33
let capBottom = NSColor(srgbRed: 0.106, green: 0.106, blue: 0.125, alpha: 1) // #1b1b20

struct Squaddie {
    let body: NSColor, stem: NSColor, name: String, family: String
}
let klik = Squaddie(body: NSColor(srgbRed: 0.357, green: 0.549, blue: 1.0, alpha: 1),
                    stem: NSColor(srgbRed: 0.227, green: 0.373, blue: 0.851, alpha: 1),
                    name: "Klik", family: "Clicky")
let bump = Squaddie(body: NSColor(srgbRed: 0.690, green: 0.537, blue: 0.408, alpha: 1),
                    stem: NSColor(srgbRed: 0.541, green: 0.400, blue: 0.278, alpha: 1),
                    name: "Bump", family: "Tactile")
let glide = Squaddie(body: NSColor(srgbRed: 1.0, green: 0.478, blue: 0.612, alpha: 1),
                     stem: NSColor(srgbRed: 0.851, green: 0.325, blue: 0.435, alpha: 1),
                     name: "Glide", family: "Linear")
let dome = Squaddie(body: NSColor(srgbRed: 0.718, green: 0.541, blue: 1.0, alpha: 1),
                    stem: NSColor(srgbRed: 0.486, green: 0.302, blue: 1.0, alpha: 1),
                    name: "Dome", family: "Thocky")

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
func easeOutBack(_ t: CGFloat) -> CGFloat {
    let x = min(max(t, 0), 1), c1: CGFloat = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}
func clamp01(_ t: CGFloat) -> CGFloat { min(max(t, 0), 1) }
func window(_ t: CGFloat, _ start: CGFloat, _ end: CGFloat, fadeIn: CGFloat = 0.4, fadeOut: CGFloat = 0.4) -> CGFloat {
    if t < start || t > end { return 0 }
    return min(easeOut((t - start) / fadeIn), easeOut((end - t) / fadeOut), 1)
}

func drawBackground(_ ctx: CGContext, w: CGFloat, h: CGFloat, dotSpacing: CGFloat = 26) {
    ctx.setFillColor(bgColor.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.045).cgColor)
    var y: CGFloat = dotSpacing / 2
    while y < h {
        var x: CGFloat = dotSpacing / 2
        while x < w {
            ctx.fillEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
            x += dotSpacing
        }
        y += dotSpacing
    }
}

func measureText(_ string: String, size: CGFloat, weight: NSFont.Weight, mono: Bool = false) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
    return CTLineGetBoundsWithOptions(line, .useOpticalBounds).width
}

func drawText(_ ctx: CGContext, _ string: String, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, center: CGPoint, alpha: CGFloat, mono: Bool = false) {
    guard alpha > 0.01 else { return }
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.withAlphaComponent(alpha)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.midY)
    CTLineDraw(line, ctx)
}

func rounded(_ ctx: CGContext, _ rect: CGRect, _ radius: CGFloat, fill: NSColor?, stroke: NSColor? = nil, lineWidth: CGFloat = 0) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if let fill {
        ctx.addPath(path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
    }
    if let stroke, lineWidth > 0 {
        ctx.addPath(path)
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
    }
}

func strokePath(_ ctx: CGContext, _ color: NSColor, _ width: CGFloat, _ build: (CGMutablePath) -> Void) {
    let p = CGMutablePath()
    build(p)
    ctx.addPath(p)
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.strokePath()
}

// MARK: - characters (coordinates are y-up)

/// Thocky. s = body width. press 0..1 sinks the cap. bubble 0..1 scales the thock! bubble.
func drawThocky(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat, alpha: CGFloat,
                bubble: CGFloat = 1, motionLines: Bool = true, press: CGFloat = 0) {
    guard alpha > 0.01 else { return }
    ctx.saveGState()
    ctx.setAlpha(alpha)
    let sink = s * 0.06 * press

    // feet
    rounded(ctx, CGRect(x: cx - 0.29 * s, y: cy - 0.46 * s, width: 0.17 * s, height: 0.075 * s), 0.037 * s, fill: ink)
    rounded(ctx, CGRect(x: cx + 0.12 * s, y: cy - 0.46 * s, width: 0.17 * s, height: 0.075 * s), 0.037 * s, fill: ink)

    // arms (waving up)
    strokePath(ctx, ink, 0.05 * s) { p in
        p.move(to: CGPoint(x: cx - 0.48 * s, y: cy - 0.02 * s - sink))
        p.addQuadCurve(to: CGPoint(x: cx - 0.68 * s, y: cy + 0.14 * s - sink),
                       control: CGPoint(x: cx - 0.64 * s, y: cy + 0.02 * s - sink))
        p.move(to: CGPoint(x: cx + 0.48 * s, y: cy - 0.02 * s - sink))
        p.addQuadCurve(to: CGPoint(x: cx + 0.68 * s, y: cy + 0.14 * s - sink),
                       control: CGPoint(x: cx + 0.64 * s, y: cy + 0.02 * s - sink))
    }

    // lip + body
    rounded(ctx, CGRect(x: cx - 0.5 * s, y: cy - 0.455 * s, width: s, height: 0.70 * s), 0.15 * s, fill: accentDark)
    let body = CGRect(x: cx - 0.5 * s, y: cy - 0.385 * s - sink, width: s, height: 0.77 * s)
    rounded(ctx, body, 0.15 * s, fill: accent, stroke: ink, lineWidth: 0.027 * s)

    // eyes
    for side: CGFloat in [-1, 1] {
        let ex = cx + side * 0.17 * s, ey = cy + 0.09 * s - sink
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: ex - 0.105 * s, y: ey - 0.105 * s, width: 0.21 * s, height: 0.21 * s))
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(0.019 * s)
        ctx.strokeEllipse(in: CGRect(x: ex - 0.105 * s, y: ey - 0.105 * s, width: 0.21 * s, height: 0.21 * s))
        ctx.setFillColor(ink.cgColor)
        ctx.fillEllipse(in: CGRect(x: ex - 0.045 * s + side * 0.012 * s, y: ey - 0.065 * s, width: 0.09 * s, height: 0.09 * s))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: ex + side * 0.012 * s, y: ey - 0.01 * s, width: 0.032 * s, height: 0.032 * s))
    }

    // smile + blush
    strokePath(ctx, ink, 0.027 * s) { p in
        p.move(to: CGPoint(x: cx - 0.088 * s, y: cy - 0.10 * s - sink))
        p.addQuadCurve(to: CGPoint(x: cx + 0.088 * s, y: cy - 0.10 * s - sink),
                       control: CGPoint(x: cx, y: cy - 0.185 * s - sink))
    }
    ctx.setFillColor(pinkBlush.withAlphaComponent(0.85).cgColor)
    ctx.fillEllipse(in: CGRect(x: cx - 0.345 * s, y: cy - 0.09 * s - sink, width: 0.092 * s, height: 0.092 * s))
    ctx.fillEllipse(in: CGRect(x: cx + 0.253 * s, y: cy - 0.09 * s - sink, width: 0.092 * s, height: 0.092 * s))

    // motion lines
    if motionLines {
        strokePath(ctx, sun, 0.03 * s) { p in
            p.move(to: CGPoint(x: cx - 0.33 * s, y: cy + 0.52 * s)); p.addLine(to: CGPoint(x: cx - 0.40 * s, y: cy + 0.66 * s))
            p.move(to: CGPoint(x: cx - 0.14 * s, y: cy + 0.56 * s)); p.addLine(to: CGPoint(x: cx - 0.17 * s, y: cy + 0.71 * s))
            p.move(to: CGPoint(x: cx + 0.05 * s, y: cy + 0.55 * s)); p.addLine(to: CGPoint(x: cx + 0.11 * s, y: cy + 0.69 * s))
        }
    }

    // thock! bubble
    if bubble > 0.02 {
        let b = bubble
        let bx = cx + 0.56 * s, by = cy + 0.53 * s
        let rx = 0.29 * s * b, ry = 0.17 * s * b
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: bx - 0.12 * s * b, y: by - ry * 0.75))
        tail.addLine(to: CGPoint(x: bx - 0.24 * s * b, y: by - ry * 1.7))
        tail.addLine(to: CGPoint(x: bx - 0.01 * s * b, y: by - ry * 0.95))
        tail.closeSubpath()
        ctx.addPath(tail)
        ctx.setFillColor(sun.cgColor)
        ctx.fillPath()
        ctx.setFillColor(sun.cgColor)
        ctx.fillEllipse(in: CGRect(x: bx - rx, y: by - ry, width: rx * 2, height: ry * 2))
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(0.02 * s)
        ctx.strokeEllipse(in: CGRect(x: bx - rx, y: by - ry, width: rx * 2, height: ry * 2))
        drawText(ctx, "thock!", size: 0.115 * s * b, weight: .bold, color: ink,
                 center: CGPoint(x: bx, y: by), alpha: 1, mono: true)
    }
    ctx.restoreGState()
}

/// A switch-squad character. u = body width.
func drawSquaddie(_ ctx: CGContext, _ who: Squaddie, cx: CGFloat, cy: CGFloat, u: CGFloat, alpha: CGFloat) {
    guard alpha > 0.01 else { return }
    ctx.saveGState()
    ctx.setAlpha(alpha)
    let lw = 0.033 * u

    if who.name == "Dome" {
        // headphone band behind the body
        strokePath(ctx, ink, 0.07 * u) { p in
            p.move(to: CGPoint(x: cx - 0.40 * u, y: cy + 0.12 * u))
            p.addQuadCurve(to: CGPoint(x: cx + 0.40 * u, y: cy + 0.12 * u),
                           control: CGPoint(x: cx, y: cy + 0.78 * u))
        }
    } else {
        // stem tab
        rounded(ctx, CGRect(x: cx - 0.145 * u, y: cy + 0.36 * u, width: 0.29 * u, height: 0.17 * u),
                0.048 * u, fill: who.stem, stroke: ink, lineWidth: lw)
    }

    // body
    rounded(ctx, CGRect(x: cx - 0.5 * u, y: cy - 0.395 * u, width: u, height: 0.79 * u),
            0.19 * u, fill: who.body, stroke: ink, lineWidth: lw)

    switch who.name {
    case "Klik":
        // excited > < eyes, open mouth, sparks
        strokePath(ctx, ink, lw) { p in
            p.move(to: CGPoint(x: cx - 0.29 * u, y: cy + 0.14 * u))
            p.addLine(to: CGPoint(x: cx - 0.18 * u, y: cy + 0.07 * u))
            p.addLine(to: CGPoint(x: cx - 0.29 * u, y: cy
                + 0.00 * u))
            p.move(to: CGPoint(x: cx + 0.29 * u, y: cy + 0.14 * u))
            p.addLine(to: CGPoint(x: cx + 0.18 * u, y: cy + 0.07 * u))
            p.addLine(to: CGPoint(x: cx + 0.29 * u, y: cy + 0.00 * u))
        }
        ctx.setFillColor(ink.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 0.095 * u, y: cy - 0.24 * u, width: 0.19 * u, height: 0.21 * u))
        ctx.setFillColor(pinkBlush.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 0.054 * u, y: cy - 0.225 * u, width: 0.108 * u, height: 0.10 * u))
        strokePath(ctx, sun, 0.028 * u) { p in
            p.move(to: CGPoint(x: cx - 0.62 * u, y: cy + 0.42 * u)); p.addLine(to: CGPoint(x: cx - 0.55 * u, y: cy + 0.32 * u))
            p.move(to: CGPoint(x: cx - 0.48 * u, y: cy + 0.50 * u)); p.addLine(to: CGPoint(x: cx - 0.46 * u, y: cy + 0.37 * u))
            p.move(to: CGPoint(x: cx + 0.62 * u, y: cy + 0.42 * u)); p.addLine(to: CGPoint(x: cx + 0.55 * u, y: cy + 0.32 * u))
            p.move(to: CGPoint(x: cx + 0.48 * u, y: cy + 0.50 * u)); p.addLine(to: CGPoint(x: cx + 0.46 * u, y: cy + 0.37 * u))
        }
    case "Bump":
        strokePath(ctx, ink, lw) { p in
            p.move(to: CGPoint(x: cx - 0.33 * u, y: cy + 0.06 * u))
            p.addQuadCurve(to: CGPoint(x: cx - 0.16 * u, y: cy + 0.06 * u),
                           control: CGPoint(x: cx - 0.245 * u, y: cy + 0.17 * u))
            p.move(to: CGPoint(x: cx + 0.16 * u, y: cy + 0.06 * u))
            p.addQuadCurve(to: CGPoint(x: cx + 0.33 * u, y: cy + 0.06 * u),
                           control: CGPoint(x: cx + 0.245 * u, y: cy + 0.17 * u))
            p.move(to: CGPoint(x: cx - 0.12 * u, y: cy - 0.10 * u))
            p.addQuadCurve(to: CGPoint(x: cx + 0.12 * u, y: cy - 0.10 * u),
                           control: CGPoint(x: cx, y: cy - 0.20 * u))
        }
        ctx.setFillColor(pinkBlush.withAlphaComponent(0.8).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 0.40 * u, y: cy - 0.11 * u, width: 0.10 * u, height: 0.10 * u))
        ctx.fillEllipse(in: CGRect(x: cx + 0.30 * u, y: cy - 0.11 * u, width: 0.10 * u, height: 0.10 * u))
    case "Glide":
        rounded(ctx, CGRect(x: cx - 0.355 * u, y: cy + 0.01 * u, width: 0.71 * u, height: 0.145 * u),
                0.072 * u, fill: ink)
        strokePath(ctx, ink, lw) { p in
            p.move(to: CGPoint(x: cx - 0.10 * u, y: cy - 0.15 * u))
            p.addQuadCurve(to: CGPoint(x: cx + 0.10 * u, y: cy - 0.15 * u),
                           control: CGPoint(x: cx, y: cy - 0.225 * u))
        }
    case "Dome":
        rounded(ctx, CGRect(x: cx - 0.575 * u, y: cy - 0.03 * u, width: 0.165 * u, height: 0.27 * u),
                0.07 * u, fill: who.stem, stroke: ink, lineWidth: lw)
        rounded(ctx, CGRect(x: cx + 0.41 * u, y: cy - 0.03 * u, width: 0.165 * u, height: 0.27 * u),
                0.07 * u, fill: who.stem, stroke: ink, lineWidth: lw)
        strokePath(ctx, ink, lw) { p in
            p.move(to: CGPoint(x: cx - 0.30 * u, y: cy + 0.07 * u))
            p.addQuadCurve(to: CGPoint(x: cx - 0.16 * u, y: cy + 0.07 * u),
                           control: CGPoint(x: cx - 0.23 * u, y: cy + 0.15 * u))
            p.move(to: CGPoint(x: cx + 0.16 * u, y: cy + 0.07 * u))
            p.addQuadCurve(to: CGPoint(x: cx + 0.30 * u, y: cy + 0.07 * u),
                           control: CGPoint(x: cx + 0.23 * u, y: cy + 0.15 * u))
            p.move(to: CGPoint(x: cx - 0.10 * u, y: cy - 0.11 * u))
            p.addQuadCurve(to: CGPoint(x: cx + 0.10 * u, y: cy - 0.11 * u),
                           control: CGPoint(x: cx, y: cy - 0.185 * u))
        }
        ctx.setFillColor(pinkBlush.withAlphaComponent(0.8).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 0.38 * u, y: cy - 0.10 * u, width: 0.095 * u, height: 0.095 * u))
        ctx.fillEllipse(in: CGRect(x: cx + 0.285 * u, y: cy - 0.10 * u, width: 0.095 * u, height: 0.095 * u))
    default: break
    }
    ctx.restoreGState()
}

/// A plain wordmark keycap. press 0..1 animates the key sinking.
func drawKeycap(_ ctx: CGContext, center: CGPoint, size: CGFloat, letter: String,
                press: CGFloat, isAccent: Bool, alpha: CGFloat) {
    guard alpha > 0.01 else { return }
    let travel = size * 0.055 * press
    let capRect = CGRect(x: center.x - size / 2, y: center.y - size / 2 - travel, width: size, height: size)
    let radius = size * 0.18
    ctx.saveGState()
    ctx.setAlpha(alpha)
    rounded(ctx, capRect.offsetBy(dx: 0, dy: -size * 0.07 + travel), radius, fill: NSColor.black.withAlphaComponent(0.85))
    if isAccent {
        rounded(ctx, capRect.offsetBy(dx: 0, dy: -size * 0.035), radius, fill: accentDark)
        rounded(ctx, capRect, radius, fill: accent, stroke: ink, lineWidth: size * 0.025)
    } else {
        let path = CGPath(roundedRect: capRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [capTop.cgColor, capBottom.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: capRect.midX, y: capRect.maxY),
                               end: CGPoint(x: capRect.midX, y: capRect.minY), options: [])
        ctx.resetClip()
    }
    drawText(ctx, letter, size: size * 0.42, weight: .heavy, color: .white,
             center: CGPoint(x: capRect.midX, y: capRect.midY + size * 0.02), alpha: 1, mono: true)
    ctx.restoreGState()
}

let word = "MACANIKAL"
let letterTimes: [CGFloat] = (0..<9).map { 0.6 + 0.35 * CGFloat($0) }

func drawWordmark(_ ctx: CGContext, center: CGPoint, capSize: CGFloat, t: CGFloat, alpha: CGFloat) {
    let gap = capSize * 0.13
    let total = CGFloat(word.count) * capSize + CGFloat(word.count - 1) * gap
    var x = center.x - total / 2 + capSize / 2
    for (i, ch) in word.enumerated() {
        let born = letterTimes[i]
        if t >= born {
            let age = t - born
            let press = age < 0.16 ? 1 - easeOut(age / 0.16) : 0
            drawKeycap(ctx, center: CGPoint(x: x, y: center.y), size: capSize, letter: String(ch),
                       press: press, isAccent: i == 3, alpha: alpha)
        }
        x += capSize + gap
    }
}

// MARK: - video timeline (15.0 s)

let W: CGFloat = 1920, H: CGFloat = 1080
let fps = 30
let duration: CGFloat = 15.0
let squadCast = [klik, bump, glide, dome]
let squadTimes: [CGFloat] = [8.0, 8.9, 9.8, 10.7]

func renderFrame(_ ctx: CGContext, t: CGFloat) {
    drawBackground(ctx, w: W, h: H)

    // Scene A: wordmark types itself
    let aAlpha = window(t, 0, 4.4, fadeIn: 0.01, fadeOut: 0.4)
    if aAlpha > 0 {
        drawWordmark(ctx, center: CGPoint(x: W / 2, y: H * 0.52), capSize: 150, t: t, alpha: aAlpha)
    }

    // Scene B: Thocky drops in + headline
    let bAlpha = window(t, 4.2, 7.8, fadeIn: 0.3, fadeOut: 0.4)
    if bAlpha > 0 {
        let drop = easeOutBack(clamp01((t - 4.2) / 0.55))
        let ty = H + 250 - (H + 250 - 690) * drop
        let landed = t >= 4.6
        let press: CGFloat = t > 4.6 && t < 4.78 ? 1 - easeOut((t - 4.6) / 0.18) : 0
        let bubbleScale = landed ? easeOutBack(clamp01((t - 5.5) / 0.28)) : 0
        drawThocky(ctx, cx: W / 2, cy: ty, s: 260, alpha: bAlpha,
                   bubble: bubbleScale, motionLines: landed, press: press)

        let h1 = window(t, 5.1, 7.8, fadeIn: 0.45, fadeOut: 0.4)
        drawText(ctx, "Your keyboard,", size: 96, weight: .bold, color: textColor,
                 center: CGPoint(x: W / 2, y: H * 0.40), alpha: h1)
        let h2 = window(t, 5.45, 7.8, fadeIn: 0.45, fadeOut: 0.4)
        let seg1 = "but it goes", seg2 = "thock."
        let w1 = measureText(seg1, size: 96, weight: .bold)
        let w2 = measureText(seg2, size: 96, weight: .heavy)
        let gap: CGFloat = 26
        let startX = W / 2 - (w1 + gap + w2) / 2
        drawText(ctx, seg1, size: 96, weight: .bold, color: textColor,
                 center: CGPoint(x: startX + w1 / 2, y: H * 0.29), alpha: h2)
        drawText(ctx, seg2, size: 96, weight: .heavy, color: accent,
                 center: CGPoint(x: startX + w1 + gap + w2 / 2, y: H * 0.29), alpha: h2)
        let sub = window(t, 6.1, 7.8, fadeIn: 0.4, fadeOut: 0.4)
        drawText(ctx, "Real mechanical switch sounds for your Mac", size: 40, weight: .medium,
                 color: mutedColor, center: CGPoint(x: W / 2, y: H * 0.185), alpha: sub)
    }

    // Scene C: the switch squad
    let cAlpha = window(t, 7.9, 11.6, fadeIn: 0.3, fadeOut: 0.4)
    if cAlpha > 0 {
        let title = window(t, 7.9, 11.6, fadeIn: 0.4, fadeOut: 0.4)
        drawText(ctx, "Meet the switch squad", size: 64, weight: .bold, color: textColor,
                 center: CGPoint(x: W / 2, y: H * 0.78), alpha: title)
        let xs: [CGFloat] = [W / 2 - 570, W / 2 - 190, W / 2 + 190, W / 2 + 570]
        for (i, who) in squadCast.enumerated() {
            let a = window(t, squadTimes[i], 11.6, fadeIn: 0.3, fadeOut: 0.4)
            guard a > 0 else { continue }
            let pop = easeOutBack(clamp01((t - squadTimes[i]) / 0.3))
            let cy = H * 0.47 + (1 - pop) * 60
            drawSquaddie(ctx, who, cx: xs[i], cy: cy, u: 210, alpha: a)
            drawText(ctx, who.name, size: 38, weight: .bold, color: textColor,
                     center: CGPoint(x: xs[i], y: cy - 200), alpha: a)
            drawText(ctx, who.family, size: 26, weight: .medium, color: mutedColor,
                     center: CGPoint(x: xs[i], y: cy - 245), alpha: a)
        }
    }

    // Scene D: CTA
    let d = window(t, 11.7, 15.0, fadeIn: 0.4, fadeOut: 0.6)
    if d > 0 {
        let press: CGFloat = t > 11.95 && t < 12.15 ? 1 - easeOut((t - 11.95) / 0.2) : 0
        drawThocky(ctx, cx: W / 2, cy: H * 0.64, s: 200, alpha: d, bubble: t > 12.0 ? 1 : 0,
                   motionLines: false, press: press)
        drawText(ctx, "Macanikal", size: 88, weight: .bold, color: textColor,
                 center: CGPoint(x: W / 2, y: H * 0.40), alpha: d)
        drawText(ctx, "free & open source · macOS 14+", size: 36, weight: .medium, color: mutedColor,
                 center: CGPoint(x: W / 2, y: H * 0.30), alpha: d)
        drawText(ctx, "github.com/techieasif/macanikal", size: 44, weight: .semibold, color: accent,
                 center: CGPoint(x: W / 2, y: H * 0.20), alpha: d, mono: true)
        drawText(ctx, "try it in your browser — techieasif.github.io/macanikal", size: 30, weight: .medium,
                 color: mutedColor, center: CGPoint(x: W / 2, y: H * 0.115), alpha: d)
    }
}

// MARK: - static assets

func renderLogo(square: Int, transparent: Bool, url: URL) {
    let ctx = makeContext(square, square)
    let s = CGFloat(square)
    if !transparent { drawBackground(ctx, w: s, h: s, dotSpacing: s / 24) }
    drawThocky(ctx, cx: s / 2, cy: s * 0.46, s: s * 0.52, alpha: 1, bubble: 1)
    savePNG(ctx, to: url)
}

func renderBanner(w: Int, h: Int, url: URL) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    drawBackground(ctx, w: W, h: H)
    drawThocky(ctx, cx: W * 0.20, cy: H * 0.52, s: W * 0.155, alpha: 1, bubble: 1)
    let tx = W * 0.63
    drawWordmark(ctx, center: CGPoint(x: tx, y: H * 0.68), capSize: W * 0.056, t: 100, alpha: 1)
    let size1 = W * 0.026
    let seg1 = "Your keyboard, but it goes", seg2 = "thock."
    let w1 = measureText(seg1, size: size1, weight: .bold)
    let w2 = measureText(seg2, size: size1, weight: .heavy)
    let gap = size1 * 0.30
    let startX = tx - (w1 + gap + w2) / 2
    drawText(ctx, seg1, size: size1, weight: .bold, color: textColor,
             center: CGPoint(x: startX + w1 / 2, y: H * 0.42), alpha: 1)
    drawText(ctx, seg2, size: size1, weight: .heavy, color: accent,
             center: CGPoint(x: startX + w1 + gap + w2 / 2, y: H * 0.42), alpha: 1)
    drawText(ctx, "Real mechanical switch sounds for your Mac · free & open source", size: W * 0.0145,
             weight: .medium, color: mutedColor, center: CGPoint(x: tx, y: H * 0.29), alpha: 1)
    drawText(ctx, "github.com/techieasif/macanikal", size: W * 0.014, weight: .semibold, color: accent,
             center: CGPoint(x: tx, y: H * 0.17), alpha: 1, mono: true)
    savePNG(ctx, to: url)
}

func renderSquadCard(w: Int, h: Int, url: URL) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    drawBackground(ctx, w: W, h: H)
    let size1 = W * 0.036
    let seg1 = "Your keyboard, but it goes", seg2 = "thock."
    let w1 = measureText(seg1, size: size1, weight: .bold)
    let w2 = measureText(seg2, size: size1, weight: .heavy)
    let gap = size1 * 0.3
    let startX = W / 2 - (w1 + gap + w2) / 2
    drawText(ctx, seg1, size: size1, weight: .bold, color: textColor,
             center: CGPoint(x: startX + w1 / 2, y: H * 0.83), alpha: 1)
    drawText(ctx, seg2, size: size1, weight: .heavy, color: accent,
             center: CGPoint(x: startX + w1 + gap + w2 / 2, y: H * 0.83), alpha: 1)
    drawThocky(ctx, cx: W * 0.20, cy: H * 0.46, s: W * 0.15, alpha: 1, bubble: 1)
    let xs: [CGFloat] = [W * 0.46, W * 0.61, W * 0.76, W * 0.91]
    for (i, who) in squadCast.enumerated() {
        drawSquaddie(ctx, who, cx: xs[i], cy: H * 0.47, u: W * 0.085, alpha: 1)
        drawText(ctx, who.name, size: W * 0.017, weight: .bold, color: textColor,
                 center: CGPoint(x: xs[i], y: H * 0.30), alpha: 1)
        drawText(ctx, who.family, size: W * 0.012, weight: .medium, color: mutedColor,
                 center: CGPoint(x: xs[i], y: H * 0.255), alpha: 1)
    }
    drawText(ctx, "github.com/techieasif/macanikal  ·  techieasif.github.io/macanikal", size: W * 0.014,
             weight: .semibold, color: accent, center: CGPoint(x: W / 2, y: H * 0.12), alpha: 1, mono: true)
    savePNG(ctx, to: url)
}

/// App icon: Thocky's face on a keycap, readable down to 16 px.
func renderIcon(square: Int, url: URL) {
    let ctx = makeContext(square, square)
    let s = CGFloat(square)
    let lw = max(1, 0.02 * s)
    rounded(ctx, CGRect(x: 0.08 * s, y: 0.075 * s, width: 0.84 * s, height: 0.77 * s), 0.19 * s, fill: accentDark)
    rounded(ctx, CGRect(x: 0.08 * s, y: 0.14 * s, width: 0.84 * s, height: 0.78 * s), 0.19 * s,
            fill: accent, stroke: ink, lineWidth: lw)
    let cy = 0.53 * s
    for side: CGFloat in [-1, 1] {
        let ex = s / 2 + side * 0.155 * s, ey = cy + 0.07 * s
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: ex - 0.10 * s, y: ey - 0.10 * s, width: 0.20 * s, height: 0.20 * s))
        if square >= 64 {
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(0.018 * s)
            ctx.strokeEllipse(in: CGRect(x: ex - 0.10 * s, y: ey - 0.10 * s, width: 0.20 * s, height: 0.20 * s))
        }
        ctx.setFillColor(ink.cgColor)
        ctx.fillEllipse(in: CGRect(x: ex - 0.045 * s + side * 0.01 * s, y: ey - 0.062 * s, width: 0.088 * s, height: 0.088 * s))
        if square >= 64 {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: ex + side * 0.012 * s, y: ey - 0.008 * s, width: 0.03 * s, height: 0.03 * s))
        }
    }
    strokePath(ctx, ink, 0.03 * s) { p in
        p.move(to: CGPoint(x: s / 2 - 0.085 * s, y: cy - 0.12 * s))
        p.addQuadCurve(to: CGPoint(x: s / 2 + 0.085 * s, y: cy - 0.12 * s),
                       control: CGPoint(x: s / 2, y: cy - 0.20 * s))
    }
    if square >= 64 {
        ctx.setFillColor(pinkBlush.withAlphaComponent(0.85).cgColor)
        ctx.fillEllipse(in: CGRect(x: s / 2 - 0.335 * s, y: cy - 0.10 * s, width: 0.085 * s, height: 0.085 * s))
        ctx.fillEllipse(in: CGRect(x: s / 2 + 0.25 * s, y: cy - 0.10 * s, width: 0.085 * s, height: 0.085 * s))
    }
    savePNG(ctx, to: url)
}

// MARK: - run

if mode == "icon-only" || mode == "all" {
    let iconset = assetsDir.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    let sizes: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, px) in sizes {
        renderIcon(square: px, url: iconset.appendingPathComponent(name + ".png"))
    }
    print("iconset done")
}

if mode != "icon-only" {
    renderLogo(square: 1024, transparent: false, url: assetsDir.appendingPathComponent("logo.png"))
    renderLogo(square: 1024, transparent: true, url: assetsDir.appendingPathComponent("logo-transparent.png"))
    renderBanner(w: 1280, h: 640, url: assetsDir.appendingPathComponent("og-banner.png"))
    renderSquadCard(w: 1600, h: 900, url: assetsDir.appendingPathComponent("x-card.png"))
    print("assets done")
}

if mode == "all" {
    let totalFrames = Int(duration * CGFloat(fps))
    for f in 0..<totalFrames {
        let ctx = makeContext(Int(W), Int(H))
        renderFrame(ctx, t: CGFloat(f) / CGFloat(fps))
        savePNG(ctx, to: framesDir.appendingPathComponent(String(format: "%04d.png", f)))
        if f % 90 == 0 { print("frame \(f)/\(totalFrames)") }
    }
    print("frames done")
}
