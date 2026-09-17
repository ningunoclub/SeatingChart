import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SeatingChart

@Suite("Photo encoding")
final class PhotoEncoderTests {
    private let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SeatingChartPhoto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes a PNG of the given size, optionally with a fully transparent
    /// background, so no fixtures need checking in.
    @discardableResult
    private func makePNG(width: Int, height: Int, transparent: Bool = false,
                         named name: String) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: nil, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if !transparent {
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        // A shape in the middle either way, so the image is not uniform.
        context.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))

        let image = try #require(context.makeImage())
        let url = root.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test("A large photo is shrunk to the maximum dimension")
    func downscalesLargePhotos() throws {
        let url = try makePNG(width: 3000, height: 2000, named: "large.png")
        let data = try #require(PhotoEncoder.jpegData(contentsOf: url))

        #expect(data.starts(with: [0xFF, 0xD8]), "should be a JPEG")
        let props = try properties(of: data)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == PhotoEncoder.maxDimension)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 800)

        let original = try Data(contentsOf: url).count
        #expect(data.count < original)
    }

    @Test("A photo already smaller than the maximum is not upscaled")
    func doesNotUpscale() throws {
        let url = try makePNG(width: 800, height: 600, named: "small.png")
        let data = try #require(PhotoEncoder.jpegData(contentsOf: url))
        let props = try properties(of: data)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 800)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 600)
    }

    @Test("Transparency is flattened onto white, not black")
    func flattensAlphaOntoWhite() throws {
        let url = try makePNG(width: 400, height: 400, transparent: true, named: "alpha.png")
        let data = try #require(PhotoEncoder.jpegData(contentsOf: url))

        let props = try properties(of: data)
        #expect(props[kCGImagePropertyHasAlpha] as? Bool != true)

        // The corners were transparent; they must now read as near-white.
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = try #require(pixel.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        })
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        _ = context.makeImage()
        // Reading back through a 1×1 context averages the image; a black
        // composite would drag every channel down.
        #expect(pixel[0] > 100 && pixel[1] > 100 && pixel[2] > 100,
                "a black composite would darken this to near zero")
    }

    @Test("A missing file or a non-image is reported as no photo")
    func unreadableSourcesReturnNil() throws {
        #expect(PhotoEncoder.jpegData(contentsOf: root.appendingPathComponent("nope.png")) == nil)

        let garbage = root.appendingPathComponent("notes.png")
        try Data("this is not an image".utf8).write(to: garbage)
        #expect(PhotoEncoder.jpegData(contentsOf: garbage) == nil)
    }
}
