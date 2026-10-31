// Renders the App Store creative assets: product page header (21:9) and
// search results (3:2). Usage:
//   swift tool/store/render_creative.swift FONTDIR store/app-store/raw/iphone-6.3/01-home.png store/app-store/creative BEZEL [guides]
// FONTDIR holds Google Fonts' Fraunces.ttf and DMSans.ttf variable fonts and
// assets/fonts/Fraunces-Amud.ttf. The screenshot is an iPhone 18 Pro capture
// (1206×2622) and BEZEL Apple's "iPhone 18 Pro - Black - Portrait.png" (Apple
// Design Resources), used as is. "guides" draws the safe areas instead.
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let fontDir = args[1], shotPath = args[2], outDir = args[3]
let bezelPath = args[4]
let guides = args.count > 5 && args[5] == "guides"

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

/// The bezel's screen opening as a clipping mask: the clear pixels connected
/// to its center, so the capture's corners never show past the frame's.
func openingMask(_ bezel: CGImage) -> CGImage {
  let w = bezel.width, h = bezel.height
  var rgba = [UInt8](repeating: 0, count: w * h * 4)
  let c = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.draw(bezel, in: CGRect(x: 0, y: 0, width: w, height: h))
  var mask = [UInt8](repeating: 0, count: w * h)
  var stack = [(w / 2) + (h / 2) * w]
  while let i = stack.popLast() {
    if mask[i] != 0 || rgba[i * 4 + 3] >= 128 { continue }
    mask[i] = 255
    let x = i % w
    if x > 0 { stack.append(i - 1) }
    if x < w - 1 { stack.append(i + 1) }
    if i >= w { stack.append(i - w) }
    if i < w * (h - 1) { stack.append(i + w) }
  }
  return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                 provider: CGDataProvider(data: Data(mask) as CFData)!, decode: nil, shouldInterpolate: true,
                 intent: .defaultIntent)!
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

  // phone, right: the capture in Apple's bezel, as is (no shadow), its
  // corners clipped to the bezel's opening
  let shot = NSImage(contentsOfFile: shotPath)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  let bezel = NSImage(contentsOfFile: bezelPath)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  let opening = CGRect(x: 72, y: 69, width: 1206, height: 2622)  // the bezel's screen, from the top
  precondition(shot.width == Int(opening.width) && shot.height == Int(opening.height), "an iPhone 18 Pro capture")
  let scale: CGFloat = 0.68
  let frame = CGRect(x: 2110, y: 330, width: CGFloat(bezel.width) * scale, height: CGFloat(bezel.height) * scale)
  ctx.saveGState()
  // the context is flipped; draw the images upright
  ctx.translateBy(x: 0, y: frame.maxY + frame.minY); ctx.scaleBy(x: 1, y: -1)
  ctx.clip(to: frame, mask: openingMask(bezel))
  ctx.draw(shot, in: CGRect(x: frame.minX + opening.minX * scale, y: frame.maxY - opening.maxY * scale,
                            width: opening.width * scale, height: opening.height * scale))
  ctx.resetClip()
  ctx.draw(bezel, in: frame)
  ctx.restoreGState()

  drawGuide(ctx, safe)
  save(ctx, guides ? "search-guides.png" : "search-results-3840x2560.png")
}
