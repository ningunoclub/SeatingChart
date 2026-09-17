// Renders one iconset slice: the source artwork, trimmed of its surrounding
// background, drawn into the rounded square macOS expects.
//
//   round-icon <source.png> <output.png> <pixel size>

import AppKit
import CoreGraphics
import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count == 4, let pixels = Int(arguments[3]), pixels > 0 else {
    FileHandle.standardError.write(Data("usage: round-icon <source> <output> <size>\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = NSImage(contentsOf: sourceURL),
      let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("cannot read \(sourceURL.path)\n".utf8))
    exit(3)
}

// MARK: - Trim the flat border around the artwork

/// Samples the artwork at a manageable resolution and returns its background
/// colour plus the square crop that just contains the drawing.
func analyse(_ image: CGImage) -> (background: CGColor, crop: CGRect)? {
    let scan = 512
    var buffer = [UInt8](repeating: 0, count: scan * scan * 4)
    guard let context = buffer.withUnsafeMutableBytes({ bytes in
        CGContext(data: bytes.baseAddress, width: scan, height: scan, bitsPerComponent: 8,
                  bytesPerRow: scan * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: scan, height: scan))
    guard let scanned = context.makeImage(),
          let data = scanned.dataProvider?.data as Data? else { return nil }
    data.copyBytes(to: &buffer, count: min(data.count, buffer.count))

    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let offset = (y * scan + x) * 4
        return (Int(buffer[offset]), Int(buffer[offset + 1]),
                Int(buffer[offset + 2]), Int(buffer[offset + 3]))
    }

    // The corner is background by assumption — true of any centred logo.
    let corner = pixel(0, 0)
    let tolerance = 18

    func isContent(_ x: Int, _ y: Int) -> Bool {
        let p = pixel(x, y)
        if p.a < 250 { return corner.a >= 250 }  // transparent border around opaque art
        return abs(p.r - corner.r) > tolerance
            || abs(p.g - corner.g) > tolerance
            || abs(p.b - corner.b) > tolerance
    }

    var minX = scan, minY = scan, maxX = -1, maxY = -1
    for y in 0..<scan {
        for x in 0..<scan where isContent(x, y) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }

    // Grow the box to a square so the artwork is never stretched.
    let width = CGFloat(maxX - minX + 1)
    let height = CGFloat(maxY - minY + 1)
    let side = max(width, height)
    let centreX = CGFloat(minX) + width / 2
    let centreY = CGFloat(minY) + height / 2

    let ratio = CGFloat(image.width) / CGFloat(scan)
    // The scan buffer has its origin at the bottom; `cropping(to:)` wants top-left.
    let cropSide = side * ratio
    let cropX = (centreX - side / 2) * ratio
    let cropY = (CGFloat(scan) - centreY - side / 2) * ratio

    let background = CGColor(red: CGFloat(corner.r) / 255, green: CGFloat(corner.g) / 255,
                             blue: CGFloat(corner.b) / 255,
                             alpha: corner.a == 0 ? 0 : CGFloat(corner.a) / 255)
    return (background, CGRect(x: cropX, y: cropY, width: cropSide, height: cropSide))
}

// MARK: - Render

guard let canvasContext = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(4) }

let canvas = CGFloat(pixels)
canvasContext.interpolationQuality = .high
canvasContext.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

// Apple's macOS grid: the tile fills roughly 80% of the canvas, with a corner
// radius of about 22% of the tile.
let tile = (canvas * 0.8046).rounded()
let tileInset = ((canvas - tile) / 2).rounded()
let tileRect = CGRect(x: tileInset, y: tileInset, width: tile, height: tile)
let radius = tile * 0.2237

canvasContext.addPath(CGPath(roundedRect: tileRect, cornerWidth: radius, cornerHeight: radius,
                             transform: nil))
canvasContext.clip()

let analysis = analyse(sourceImage)

if let analysis {
    // Repaint the trimmed background across the whole tile, then place the art
    // with a small margin so it never touches the rounded edge.
    canvasContext.setFillColor(analysis.background)
    canvasContext.fill(tileRect)

    let artwork = sourceImage.cropping(to: analysis.crop) ?? sourceImage
    let margin = (tile * 0.085).rounded()
    canvasContext.draw(artwork, in: tileRect.insetBy(dx: margin, dy: margin))
} else {
    canvasContext.draw(sourceImage, in: tileRect)
}

guard let rendered = canvasContext.makeImage(),
      let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
    exit(5)
}
try data.write(to: outputURL)
