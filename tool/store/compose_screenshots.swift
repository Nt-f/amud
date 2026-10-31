// Composes the captioned App Store screenshots: each simulator capture in
// Apple's product bezel (Apple Design Resources, used as is: no shadow, not
// cropped or tilted), on the brand navy, with a caption above it.
//
//   swift tool/store/compose_screenshots.swift DEVICE BEZEL FONTDIR CAPTURES OUTDIR
//
// DEVICE is iphone (the iPhone 18 Pro bezel, for "iPhone with Dynamic Island
// (medium display)", 1206×2622, the slot App Store Connect requires),
// iphone-large (iPhone 18 Pro Max, "large display", 1320×2868), duo-outer
// (1398×2034) or duo-inner (2007×2853). BEZEL is the matching portrait PNG from Apple's bezel disk
// image. CAPTURES holds simulator screenshots named as in `captions` below
// (store/app-store/raw/<device>/); FONTDIR holds Google Fonts' Fraunces.ttf
// and DMSans.ttf variable fonts.
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let device = args[1], bezelPath = args[2], fontDir = args[3], inDir = args[4], outDir = args[5]

struct Device { let canvas: CGSize; let screen: CGRect }
// The canvas is the App Store size; the screen is the bezel's opening, which
// is exactly the size of that device's capture.
let devices: [String: Device] = [
  "iphone": Device(canvas: CGSize(width: 1206, height: 2622), screen: CGRect(x: 72, y: 69, width: 1206, height: 2622)),
  "iphone-large": Device(canvas: CGSize(width: 1320, height: 2868), screen: CGRect(x: 75, y: 66, width: 1320, height: 2868)),
  "duo-outer": Device(canvas: CGSize(width: 1398, height: 2034), screen: CGRect(x: 88, y: 80, width: 1398, height: 2034)),
  "duo-inner": Device(canvas: CGSize(width: 2007, height: 2853), screen: CGRect(x: 120, y: 120, width: 2007, height: 2853)),
]
let captions: [(String, [String], String)] = [
  ("01-home", ["The siddur that knows", "what day it is"], "Today’s changes, zmanim and learning at a glance"),
  ("02-pray_shacharit", ["Hebrew and English,", "line by line"], "Ashkenaz, Sefard, Edot HaMizrach, Chabad and Koren"),
  ("03-torah_gemara_read", ["The daf, as the", "Vilna Shas prints it"], "Gemara, Rashi and Tosafos, with English"),
  ("04-zmanim", ["Zmanim for", "where you are"], "GRA, Magen Avraham or Baal HaTanya"),
  ("05-siddur", ["Every tefillah,", "one tap away"], "Brachos, Tefillas HaDerech, Krias Shema al HaMitah"),
  ("06-learning", ["Daily learning", "in one place"], "Daf Yomi, Mishnah Yomi, Rambam and more"),
  ("07-calendar", ["A full Jewish", "calendar"], "Yamim Tovim, parshiyos and Hebrew dates"),
  ("08-torah_tehillim", ["Tehillim by month", "or by week"], "Shir shel Yom, with your progress saved"),
  ("09-pray_birkat", ["Birchas Hamazon for", "every simcha"], "Bris, Sheva Brachos and Pidyon HaBen"),
]

func rgb(_ hex: UInt32) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
let ink = rgb(0x172a5c), paper = rgb(0xf8f3ea), fan = rgb(0xa9c0ee)

func font(_ file: String, _ size: CGFloat, _ axes: [String: Double]) -> CTFont {
  let url = URL(fileURLWithPath: "\(fontDir)/\(file)") as CFURL
  let desc = (CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor])[0]
  var vars: [NSNumber: NSNumber] = [:]
  for (tag, v) in axes { vars[NSNumber(value: tag.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | $1.value })] = NSNumber(value: v) }
  return CTFontCreateWithFontDescriptor(
    CTFontDescriptorCreateCopyWithAttributes(desc, [kCTFontVariationAttribute: vars] as CFDictionary), size, nil)
}
func line(_ s: String, _ f: CTFont, _ c: CGColor, kern: CGFloat = 0) -> CTLine {
  CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
    .init(kCTFontAttributeName as String): f, .init(kCTForegroundColorAttributeName as String): c, .kern: kern]))
}
func width(_ l: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) }
func image(_ path: String) -> CGImage { NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)! }

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
  let provider = CGDataProvider(data: Data(mask) as CFData)!
  return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

let d = devices[device]!
let W = d.canvas.width, H = d.canvas.height
let bezel = image(bezelPath)
let mask = openingMask(bezel)
let bezelSize = CGSize(width: bezel.width, height: bezel.height)
// type scales with the canvas's width; the iPhone canvas is the reference
let u = W / 1206

for (name, head, sub) in captions {
  let path = "\(inDir)/\(name).png"
  guard FileManager.default.fileExists(atPath: path) else { print("skip \(name)"); continue }
  let shot = image(path)
  precondition(CGFloat(shot.width) == d.screen.width && CGFloat(shot.height) == d.screen.height,
               "\(name): capture is \(shot.width)×\(shot.height), the bezel's screen is \(d.screen.size)")
  let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.setFillColor(ink); ctx.fill(CGRect(origin: .zero, size: d.canvas))

  // caption, centered; each line shrinks to fit the width if it must
  let maxW = W * 0.88
  func fitted(_ s: String, _ make: (CGFloat) -> CTFont, _ size: CGFloat, _ c: CGColor, kern: CGFloat) -> CTLine {
    var size = size, l = line(s, make(size), c, kern: kern * size)
    while width(l) > maxW { size -= 2; l = line(s, make(size), c, kern: kern * size) }
    return l
  }
  let headSize = 104 * u, subSize = 38 * u
  let display = { (s: CGFloat) in font("Fraunces.ttf", s, ["opsz": 72, "wght": 600, "SOFT": 0, "WONK": 0]) }
  let body = { (s: CGFloat) in font("DMSans.ttf", s, ["opsz": 14, "wght": 450]) }
  var y = H - 150 * u  // baseline of the first line, measured from the bottom (CG's origin)
  for s in head {
    let l = fitted(s, display, headSize, paper, kern: -0.02)
    ctx.textPosition = CGPoint(x: (W - width(l)) / 2, y: y); CTLineDraw(l, ctx)
    y -= headSize * 1.12
  }
  y -= subSize * 0.55
  let sl = fitted(sub, body, subSize, fan, kern: 0)
  ctx.textPosition = CGPoint(x: (W - width(sl)) / 2, y: y); CTLineDraw(sl, ctx)
  let captionBottom = y - subSize * 1.6

  // device: as large as fits under the caption, whole, centered
  let bottomMargin = 70 * u
  let scale = min((captionBottom - bottomMargin) / bezelSize.height, W * 0.9 / bezelSize.width)
  let frame = CGRect(x: (W - bezelSize.width * scale) / 2, y: bottomMargin,
                     width: bezelSize.width * scale, height: bezelSize.height * scale)
  // the bezel's opening, in canvas coordinates (the bezel's own are top-down)
  let screen = CGRect(x: frame.minX + d.screen.minX * scale,
                      y: frame.maxY - d.screen.maxY * scale,
                      width: d.screen.width * scale, height: d.screen.height * scale)
  ctx.saveGState()
  ctx.clip(to: frame, mask: mask)
  ctx.draw(shot, in: screen)
  ctx.restoreGState()
  ctx.draw(bezel, in: frame)

  let url = URL(fileURLWithPath: "\(outDir)/\(name).png") as CFURL
  let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
  CGImageDestinationFinalize(dest)
  print(name)
}
