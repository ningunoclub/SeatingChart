import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks a student photo for export. Deliberately ImageIO rather than
/// `NSImage`: `NSImage.size` is in points, so a Retina source would silently
/// halve, and the AppKit route drops EXIF orientation. Staying AppKit-free also
/// keeps this testable headlessly.
enum PhotoEncoder {
    /// Longest side of an exported photo. Far above anything the app draws —
    /// presentation mode is the largest at roughly 200 pt.
    static let maxDimension = 1200
    static let jpegQuality = 0.85
    static let fileExtension = "jpg"

    /// `nil` when the file is missing, unreadable or not an image. Callers treat
    /// that exactly like "this student has no photo".
    static func jpegData(contentsOf url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies EXIF orientation, which a phone photo relies on.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        // True pixel dimensions, not points.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        // Omitted entirely when the image already fits, so nothing is upscaled.
        if max(width, height) > maxDimension {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxDimension
        }

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let opaque = flattened(thumbnail) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, opaque, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// JPEG has no alpha, so a transparent PNG would composite onto black and
    /// show as a dark ring inside the avatar circle. Drawing onto white first is
    /// unconditional — it also normalises wide-gamut sources to sRGB.
    private static func flattened(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: image.width,
                                      height: image.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
