// Builds Lyra's app icon: the dark plate from ChatGPT, cut out and fitted to
// the macOS 1024 grid, with a solid white beamed note that has ASCII
// characters cut into it. The solid shape keeps it legible at Dock sizes;
// the type shows up close.
// Usage: swift scripts/make_icon.swift packaging/icon-plate.png icon.png [type size, default 34]
import AppKit
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
let platePath = args[1]
let outPath = args[2]
let fontSize = args.count > 3 ? Double(args[3])! : 34

let canvas = 1024
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824) // Apple macOS icon grid

// MARK: - Plate: load, remove the white background, crop

func loadRGBA(_ path: String) -> (data: [UInt8], w: Int, h: Int) {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = img.width, h = img.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (data, w, h)
}

var (px, pw, ph) = loadRGBA(platePath)

// The plate already has a transparent background: crop to its alpha, and
// make the inside fully opaque (it comes out at ~99%).
var minX = pw, minY = ph, maxX = 0, maxY = 0
for y in 0..<ph {
    for x in 0..<pw {
        let i = (y * pw + x) * 4
        let a = Double(px[i + 3])
        guard a > 20 else { continue }
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        if a >= 240 {
            for k in 0..<3 { px[i + k] = UInt8(min(255, Double(px[i + k]) * 255 / a)) }
            px[i + 3] = 255
        }
    }
}
let plateImage: CGImage = {
    let ctx = CGContext(data: &px, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // CGContext rows start at the bottom; the buffer's first row is the top.
    let full = ctx.makeImage()!
    return full.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
}()
FileHandle.standardError.write("plate bbox \(minX),\(minY) \(maxX - minX + 1)x\(maxY - minY + 1)\n".data(using: .utf8)!)

// MARK: - Note shape (top-left origin, 1000-unit box)

func notePath() -> CGPath {
    let p = CGMutablePath()
    // Beam, slanting up to the right.
    p.addLines(between: [CGPoint(x: 370, y: 250), CGPoint(x: 860, y: 140),
                         CGPoint(x: 860, y: 300), CGPoint(x: 370, y: 410)])
    p.closeSubpath()
    // Stems.
    p.addRect(CGRect(x: 370, y: 300, width: 96, height: 480))
    p.addRect(CGRect(x: 764, y: 200, width: 96, height: 480))
    // Noteheads: tilted ellipses whose right edge meets the stem.
    for (cx, cy) in [(296.0, 776.0), (690.0, 686.0)] {
        let t = CGAffineTransform(translationX: cx, y: cy).rotated(by: -0.40)
        p.addEllipse(in: CGRect(x: -170, y: -118, width: 340, height: 236), transform: t)
    }
    return p
}

// The note is big: it reads as a shape even at Dock and Finder sizes.
let noteInTile: CGPath = {
    let scale = tileRect.width * 0.80 / 1000
    let box = notePath().boundingBoxOfPath
    // Path units have a top-left origin; flip into the tile.
    var t = CGAffineTransform(translationX: tileRect.minX, y: tileRect.maxY)
        .scaledBy(x: 1, y: -1)
        .translatedBy(x: tileRect.width / 2 - box.midX * scale, y: tileRect.height / 2 - box.midY * scale)
        .scaledBy(x: scale, y: scale)
    return notePath().copy(using: &t)!
}()

func noise(_ a: Int, _ b: Int) -> Double {
    var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663)
    h ^= h >> 33; h &*= 0xff51_afd7_ed55_8ccd; h ^= h >> 33
    return Double(h % 10_000) / 10_000
}

// MARK: - Compose

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

// Plate with a soft drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
ctx.draw(plateImage, in: tileRect)
ctx.restoreGState()

// Solid note with a soft glow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: CGColor(gray: 1, alpha: 0.28))
ctx.addPath(noteInTile)
ctx.setFillColor(CGColor(gray: 0.96, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// ASCII cut into the note: a full grid of type in the plate's color,
// clipped to the shape, denser toward the bottom.
ctx.saveGState()
ctx.addPath(noteInTile)
ctx.clip()
let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
let charW = ("M" as NSString).size(withAttributes: [.font: font]).width
let lineH = fontSize * 1.05
let glyphs = Array("+*#%@=")
let area = noteInTile.boundingBoxOfPath
var row = 0
var y = area.maxY - lineH
while y > area.minY - lineH {
    var col = 0
    var x = area.minX
    while x < area.maxX {
        let n = noise(col, row)
        let depth = 1 - (y - area.minY) / area.height   // 0 at the top, 1 at the bottom
        let ch = glyphs[Int(n * Double(glyphs.count)) % glyphs.count]
        (String(ch) as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.09, green: 0.094, blue: 0.10, alpha: 0.55 + 0.3 * depth),
        ])
        x += charW; col += 1
    }
    y -= lineH; row += 1
}
ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
