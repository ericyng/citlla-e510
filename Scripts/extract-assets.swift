// Extracts the two mouse renders from the manufacturer's diagram as transparent
// PNGs and writes them into the asset catalog.
//
//   swift Scripts/extract-assets.swift Design/citlla-diagram.png
//
// The source is the CITLLA PRO MAX E510 product diagram: a 1500x1500 collage of
// numbered callouts plus two renders of the mouse. This tool crops each render,
// keys out the white studio background, keeps only the largest blob (so the
// callout leader lines and stray specks disappear), trims to the artwork, and
// drops a 1x and 2x copy into CitllaE510/Assets.xcassets/Mouse/.

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: extract-assets.swift <diagram.png>\n".utf8))
    exit(2)
}

let sourcePath = args[1]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("CitllaE510/Assets.xcassets")

guard let image = NSImage(contentsOfFile: sourcePath),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("cannot load \(sourcePath)\n".utf8))
    exit(1)
}

struct Crop {
    let name: String
    let rect: CGRect
    let note: String
}

// Measured from the diagram's own callout badges. The top view carries
// callouts 1-4 and 9; the side view carries 5-8. Both rects are deliberately
// generous: the trim step below cuts them back to the artwork, and a crop that
// is too tight clips the mouse's outline (the old 485-wide top crop cut 30 px
// off its right side).
let crops = [
    Crop(name: "MouseTop", rect: CGRect(x: 225, y: 575, width: 540, height: 780), note: "top view"),
    Crop(name: "MouseSide", rect: CGRect(x: 930, y: 575, width: 390, height: 760), note: "side view"),
]

func writePNG(_ pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let data = Data(pixels)
    guard let provider = CGDataProvider(data: data as CFData) else { throw NSError(domain: "assets", code: 1) }
    let alphaInfo: CGBitmapInfo = [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]
    guard let cg = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: colorSpace, bitmapInfo: alphaInfo,
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    ) else { throw NSError(domain: "assets", code: 2) }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "assets", code: 3) }
    try png.write(to: url)
}

for crop in crops {
    guard let cut = source.cropping(to: crop.rect) else {
        FileHandle.standardError.write(Data("crop failed for \(crop.name)\n".utf8))
        exit(1)
    }
    let w = cut.width, h = cut.height
    FileHandle.standardError.write(Data("  crop \(crop.name): \(w)x\(h)\n".utf8))
    var src = [UInt8](repeating: 0, count: w * h * 4)
    let drawn: Bool = src.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(
            data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(cut, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard drawn else { throw NSError(domain: "assets", code: 4) }

    // The studio background is a near-neutral gradient from white to pale grey.
    // Anything darker, or tinted like the light strips, is artwork.
    var alpha = [UInt8](repeating: 0, count: w * h)
    for i in 0..<(w * h) {
        let r = Int(src[i * 4]), g = Int(src[i * 4 + 1]), b = Int(src[i * 4 + 2])
        let lum = (r * 299 + g * 587 + b * 114) / 1000
        let chroma = max(r, max(g, b)) - min(r, min(g, b))
        let a: Int
        if chroma > 24 {
            a = 255
        } else {
            // 180 and below is solid, 210 and above is background.
            a = max(0, min(255, (210 - lum) * 255 / 30))
        }
        alpha[i] = UInt8(a)
    }

    // Erode, keep the largest blob, dilate back. The erosion breaks the thin
    // callout leader lines and the shadow strip along the bottom of the crop so
    // only the mouse itself survives.
    func erode(_ m: [Bool], _ w: Int, _ h: Int, _ radius: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: w * h)
        for y in radius..<(h - radius) {
            for x in radius..<(w - radius) {
                if !m[y * w + x] { continue }
                var all = true
                for dy in -radius...radius {
                    for dx in -radius...radius where !m[(y + dy) * w + (x + dx)] {
                        all = false
                        break
                    }
                    if !all { break }
                }
                out[y * w + x] = all
            }
        }
        return out
    }
    func dilate(_ m: [Bool], _ w: Int, _ h: Int, _ radius: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where m[y * w + x] {
                for dy in -radius...radius {
                    let ny = y + dy
                    guard ny >= 0, ny < h else { continue }
                    for dx in -radius...radius {
                        let nx = x + dx
                        guard nx >= 0, nx < w else { continue }
                        out[ny * w + nx] = true
                    }
                }
            }
        }
        return out
    }

    let solid = (0..<(w * h)).map { alpha[$0] > 128 }
    let eroded = erode(solid, w, h, 3)

    var seen = [Bool](repeating: false, count: w * h)
    var best: [Int] = []
    for start in 0..<(w * h) where eroded[start] && !seen[start] {
        var stack = [start]
        seen[start] = true
        var blob: [Int] = []
        while let p = stack.popLast() {
            blob.append(p)
            let x = p % w, y = p / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let q = ny * w + nx
                if eroded[q] && !seen[q] {
                    seen[q] = true
                    stack.append(q)
                }
            }
        }
        if blob.count > best.count { best = blob }
    }
    var body = [Bool](repeating: false, count: w * h)
    for p in best { body[p] = true }
    let keep = dilate(body, w, h, 6)

    var minX = w, minY = h, maxX = 0, maxY = 0
    for i in 0..<(w * h) where keep[i] && alpha[i] > 8 {
        let x = i % w, y = i / w
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
    let pad = 6
    let x0 = max(0, minX - pad), y0 = max(0, minY - pad)
    let x1 = min(w - 1, maxX + pad), y1 = min(h - 1, maxY + pad)

    let outW = x1 - x0 + 1, outH = y1 - y0 + 1
    var out = [UInt8](repeating: 0, count: outW * outH * 4)
    for y in 0..<outH {
        for x in 0..<outW {
            let sx = x0 + x, sy = y0 + y
            let s = sy * w + sx
            let a = keep[s] ? alpha[s] : 0
            let o = (y * outW + x) * 4
            if a == 0 { continue }
            let af = Int(a)
            out[o] = UInt8(Int(src[s * 4]) * af / 255)
            out[o + 1] = UInt8(Int(src[s * 4 + 1]) * af / 255)
            out[o + 2] = UInt8(Int(src[s * 4 + 2]) * af / 255)
            out[o + 3] = UInt8(af)
        }
    }

    let dir = assets.appendingPathComponent("Mouse/\(crop.name).imageset")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // 2x is the artwork as cropped; 1x is half size, so the pair renders crisply
    // at the sizes the UI uses without shipping the full-resolution render twice.
    try writePNG(out, width: outW, height: outH, to: dir.appendingPathComponent("\(crop.name)@2x.png"))

    let halfW = outW / 2, halfH = outH / 2
    var half = [UInt8](repeating: 0, count: halfW * halfH * 4)
    for y in 0..<halfH {
        for x in 0..<halfW {
            var r = 0, g = 0, b = 0, a = 0
            for dy in 0..<2 {
                for dx in 0..<2 {
                    let s = ((y * 2 + dy) * outW + (x * 2 + dx)) * 4
                    r += Int(out[s]); g += Int(out[s + 1]); b += Int(out[s + 2]); a += Int(out[s + 3])
                }
            }
            let o = (y * halfW + x) * 4
            half[o] = UInt8(r / 4); half[o + 1] = UInt8(g / 4)
            half[o + 2] = UInt8(b / 4); half[o + 3] = UInt8(a / 4)
        }
    }
    try writePNG(half, width: halfW, height: halfH, to: dir.appendingPathComponent("\(crop.name).png"))

    let contents = """
    {
      "images" : [
        { "filename" : "\(crop.name).png", "idiom" : "universal", "scale" : "1x" },
        { "filename" : "\(crop.name)@2x.png", "idiom" : "universal", "scale" : "2x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "preserves-vector-representation" : false }
    }
    """
    try contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    print("wrote \(crop.name) (\(crop.note)) \(outW)x\(outH) + \(halfW)x\(halfH)")
}
