// Renders the App Store creative assets: product page header (21:9) and
// search results (3:2). Usage:
//   swift tool/store/render_creative.swift FONTDIR store/app-store/raw/iphone/01-home.png store/app-store/creative [guides]
// FONTDIR holds Google Fonts' Fraunces.ttf and DMSans.ttf variable fonts and
// assets/fonts/Fraunces-Amud.ttf. "guides" draws the safe areas instead.
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let fontDir = args[1], shotPath = args[2], outDir = args[3]
let guides = args.count > 4 && args[4] == "guides"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let navy = rgb(0x172a5c), cream = rgb(0xf8f3ea), fan = rgb(0xa9c0ee), fanDeep = rgb(0x6f8cc0)

func font(_ file: String, _ size: CGFloat, _ axes: [String: Double]) -> CTFont {
  let url = URL(fileURLWithPath: "\(fontDir)/\(file)") as CFURL
  let desc = (CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor])[0]
  var vars: [NSNumber: NSNumber] = [:]
  for (tag, v) in axes {
    let t = tag.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | $1.value }
    vars[NSNumber(value: t)] = NSNumber(value: v)
  }
  let d = CTFontDescriptorCreateCopyWithAttributes(desc, [kCTFontVariationAttribute: vars] as CFDictionary)
  return CTFontCreateWithFontDescriptor(d, size, nil)
}
// The landing page's h1: Fraunces 600, tracked -0.026em.
func display(_ size: CGFloat) -> CTFont { font("Fraunces.ttf", size, ["opsz": 48, "wght": 600, "SOFT": 0, "WONK": 0]) }
// The app's own wordmark cut (assets/fonts/Fraunces-Amud.ttf: "amud" only).
func wordmark(_ size: CGFloat) -> CTFont { font("Fraunces-Amud.ttf", size, [:]) }
func body(_ size: CGFloat, _ w: Double = 500) -> CTFont { font("DMSans.ttf", size, ["opsz": 40, "wght": w]) }

func line(_ s: String, _ f: CTFont, _ c: CGColor, kern: CGFloat = 0) -> CTLine {
  CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
    .init(kCTFontAttributeName as String): f, .init(kCTForegroundColorAttributeName as String): c,
    .kern: kern]))
}
func width(_ l: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) }

/// Draws a line with its baseline at y (top-left coordinates).
func draw(_ ctx: CGContext, _ l: CTLine, x: CGFloat, baseline y: CGFloat) {
  ctx.saveGState()
  ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
  ctx.textPosition = CGPoint(x: x, y: y)
  CTLineDraw(l, ctx)
  ctx.restoreGState()
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
  ctx.interpolationQuality = .high
  return ctx
}

func save(_ ctx: CGContext, _ name: String) {
  let img = ctx.makeImage()!
  let url = URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL
  let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, img, nil)
  CGImageDestinationFinalize(dest)
}

// MARK: the Amud mark (assets/brand/amud_mark.svg), in its 16 20 168 168 viewBox

func page(_ left: Bool) -> CGPath {
  let p = CGMutablePath()
  if left {
    p.move(to: CGPoint(x: 97, y: 92))
    p.addCurve(to: CGPoint(x: 44, y: 76), control1: CGPoint(x: 84, y: 80), control2: CGPoint(x: 62, y: 75))
    p.addLine(to: CGPoint(x: 40, y: 30))
    p.addCurve(to: CGPoint(x: 97, y: 50), control1: CGPoint(x: 62, y: 29), control2: CGPoint(x: 84, y: 36))
  } else {
    p.move(to: CGPoint(x: 103, y: 92))
    p.addCurve(to: CGPoint(x: 156, y: 76), control1: CGPoint(x: 116, y: 80), control2: CGPoint(x: 138, y: 75))
    p.addLine(to: CGPoint(x: 160, y: 30))
    p.addCurve(to: CGPoint(x: 103, y: 50), control1: CGPoint(x: 116, y: 36), control2: CGPoint(x: 138, y: 29))
  }
  p.closeSubpath()
  return p
}

func drawMark(_ ctx: CGContext, center: CGPoint, size: CGFloat) {
  ctx.saveGState()
  let s = size / 168
  ctx.translateBy(x: center.x - size / 2, y: center.y - size / 2)
  ctx.scaleBy(x: s, y: s)
  ctx.translateBy(x: -16, y: -20)
  for (deg, color) in [(14.0, fanDeep), (7.0, fan), (0.0, cream)] {
    for left in [true, false] {
      ctx.saveGState()
      let pivot = CGPoint(x: left ? 97 : 103, y: 92)
      ctx.translateBy(x: pivot.x, y: pivot.y)
      ctx.rotate(by: CGFloat((left ? -deg : deg) * .pi / 180))
      ctx.translateBy(x: -pivot.x, y: -pivot.y)
      ctx.addPath(page(left)); ctx.setFillColor(color); ctx.fillPath()
      ctx.restoreGState()
    }
  }
  ctx.setStrokeColor(cream); ctx.setLineWidth(7); ctx.setLineCap(.round)
  for (x1, y1, x2, y2) in [(50, 106, 150, 106), (64, 119, 136, 119), (82, 133, 82, 172),
                           (100, 133, 100, 180), (118, 133, 118, 172)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    ctx.move(to: CGPoint(x: x1, y: y1)); ctx.addLine(to: CGPoint(x: x2, y: y2))
  }
  ctx.strokePath()
  ctx.restoreGState()
}

// MARK: background — night sky over layered open-book "hills", after Apple's
// Forest Explorer example, whose header repeats its icon's landscape.

/// The top edge of an open book's pages, spine at cx: low at the spine,
/// rising quickly, then flattening toward the edges, like the icon's pages.
func bookHill(w: CGFloat, h: CGFloat, cx: CGFloat, spine: CGFloat, rise: CGFloat, spread: CGFloat) -> CGPath {
  let p = CGMutablePath()
  let edgeY = spine - rise
  p.move(to: CGPoint(x: -10, y: h + 10))
  p.addLine(to: CGPoint(x: -10, y: edgeY + rise * 0.06))
  // left page: from far left (high) down to the spine
  p.addCurve(to: CGPoint(x: cx, y: spine),
             control1: CGPoint(x: cx - spread * 0.45, y: edgeY - rise * 0.02),
             control2: CGPoint(x: cx - spread * 0.10, y: spine))
  p.addCurve(to: CGPoint(x: w + 10, y: edgeY + rise * 0.06),
             control1: CGPoint(x: cx + spread * 0.10, y: spine),
             control2: CGPoint(x: cx + spread * 0.45, y: edgeY - rise * 0.02))
  p.addLine(to: CGPoint(x: w + 10, y: h + 10))
  p.closeSubpath()
  return p
}

func background(_ ctx: CGContext, w: CGFloat, h: CGFloat, horizon: CGFloat, cx: CGFloat, scale: CGFloat) {
  let sky = CGGradient(colorsSpace: nil, colors: [rgb(0x172a5c), rgb(0x172a5c), rgb(0x1d3369)] as CFArray,
                       locations: [0, 0.45, 1])!
  ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: horizon), options: [.drawsAfterEndLocation])
  // a soft glow over the spine
  let glow = CGGradient(colorsSpace: nil, colors: [rgb(0xa9c0ee, 0.07), rgb(0xa9c0ee, 0)] as CFArray, locations: [0, 1])!
  ctx.drawRadialGradient(glow, startCenter: CGPoint(x: cx, y: horizon * 0.62), startRadius: 0,
                         endCenter: CGPoint(x: cx, y: horizon * 0.62), endRadius: 1500 * scale, options: [])
  // far to near: lighter and higher behind, darker and lower in front
  let layers: [(UInt32, CGFloat, CGFloat, CGFloat)] = [
    (0x2a4482, 0.00, 520, 3400),
    (0x22397a, 0.10, 470, 3000),
    (0x1d3370, 0.22, 420, 2700),
    (0x182d63, 0.36, 380, 2500),
    (0x142451, 0.52, 340, 2300),
  ]
  for (hex, drop, rise, spread) in layers {
    ctx.addPath(bookHill(w: w, h: h, cx: cx, spine: horizon + drop * (h - horizon) * 0.9 + 120 * scale,
                         rise: rise * scale, spread: spread * scale))
    ctx.setFillColor(rgb(hex)); ctx.fillPath()
  }
}

func drawGuide(_ ctx: CGContext, _ r: CGRect) {
  guard guides else { return }
  ctx.setStrokeColor(rgb(0x00ff00)); ctx.setLineWidth(6); ctx.stroke(r)
}

// MARK: product page header, 3840 x 1646. Art safe area (Apple's template):
// x 1099–2736, y 494–1150, centered.

do {
  let w: CGFloat = 3840, h: CGFloat = 1646
  let ctx = makeContext(Int(w), Int(h))
  background(ctx, w: w, h: h, horizon: 1230, cx: w / 2, scale: 1)
  let safe = CGRect(x: 1099, y: 494, width: 1640, height: 656)
  // the launch screen's lockup: the mark over a lowercase wordmark
  drawMark(ctx, center: CGPoint(x: w / 2, y: 690), size: 380)
  let word = line("amud", wordmark(190), cream, kern: -5)
  draw(ctx, word, x: (w - width(word)) / 2, baseline: 1080)
  drawGuide(ctx, safe)
  save(ctx, guides ? "header-guides.png" : "header-3840x1646.png")
}

// MARK: search results, 3840 x 2560. Art safe area: x 840–3000, y 766–1790.

do {
  let w: CGFloat = 3840, h: CGFloat = 2560
  let ctx = makeContext(Int(w), Int(h))
  background(ctx, w: w, h: h, horizon: 1650, cx: 2560, scale: 1.25)
  let safe = CGRect(x: 840, y: 766, width: 2160, height: 1024)

  // headline, left
  let x: CGFloat = 860
  let head = ["The siddur that", "knows the day"].map { line($0, display(168), cream, kern: -4.4) }
  draw(ctx, head[0], x: x, baseline: 1160)
  draw(ctx, head[1], x: x, baseline: 1160 + 196)
  let sub = ["Only what’s said today, in your nusach.", "Zmanim and daily learning beside it."]
    .map { line($0, body(62, 400), rgb(0xd6def0)) }
  draw(ctx, sub[0], x: x + 6, baseline: 1500)
  draw(ctx, sub[1], x: x + 6, baseline: 1500 + 86)

  // phone, right
  let shot = NSImage(contentsOfFile: shotPath)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  let screenW: CGFloat = 820
  let screenH = screenW * CGFloat(shot.height) / CGFloat(shot.width)
  let bezel: CGFloat = 34
  let screen = CGRect(x: 2160, y: 390, width: screenW, height: screenH)
  let body = screen.insetBy(dx: -bezel, dy: -bezel)
  let radius: CGFloat = screenW * 0.135
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: 40), blur: 120, color: rgb(0x050a1a, 0.6))
  ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
  ctx.setFillColor(rgb(0x0b0f1a)); ctx.fillPath()
  ctx.restoreGState()
  ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 5, dy: 5), cornerWidth: radius + bezel - 5,
                     cornerHeight: radius + bezel - 5, transform: nil))
  ctx.setStrokeColor(rgb(0x4a5a80)); ctx.setLineWidth(6); ctx.strokePath()
  ctx.saveGState()
  ctx.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil))
  ctx.clip()
  // the context is flipped; flip the image back
  ctx.translateBy(x: 0, y: screen.maxY + screen.minY); ctx.scaleBy(x: 1, y: -1)
  ctx.draw(shot, in: screen)
  ctx.restoreGState()
  // Dynamic Island
  let island = CGRect(x: screen.midX - screenW * 0.155, y: screen.minY + screenW * 0.03,
                      width: screenW * 0.31, height: screenW * 0.092)
  ctx.addPath(CGPath(roundedRect: island, cornerWidth: island.height / 2, cornerHeight: island.height / 2, transform: nil))
  ctx.setFillColor(rgb(0x000000)); ctx.fillPath()

  drawGuide(ctx, safe)
  save(ctx, guides ? "search-guides.png" : "search-results-3840x2560.png")
}
