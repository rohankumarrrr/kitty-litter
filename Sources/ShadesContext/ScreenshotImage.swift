import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Marks up and encodes a capture. Pure image work, so it runs without any permissions.
enum ScreenshotImage {
    static let longSide: CGFloat = 2048
    static let quality = 0.8
    /// T3's attachment limit is 10 MB, so stay a little under it.
    static let byteLimit = 10_000_000

    /// Draws the red rectangle around a region given in pixels with a top-left origin.
    static func marked(_ image: CGImage, region: CGRect) -> CGImage? {
        let width = image.width
        let height = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)

        let line = strokeWidth(forLongSide: max(width, height))
        // Quartz contexts draw from the bottom left. The stroke sits just outside the region so it
        // covers none of what you pointed at, but stays on the image when the region meets an edge.
        let flipped = CGRect(
            x: region.minX,
            y: CGFloat(height) - region.maxY,
            width: region.width,
            height: region.height
        )
        let box = flipped.insetBy(dx: -line / 2, dy: -line / 2)
            .intersection(bounds.insetBy(dx: line / 2, dy: line / 2))
        guard !box.isNull else { return context.makeImage() }

        // A thin white edge keeps the mark readable on red and on dark backgrounds.
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
        context.setLineWidth(line + 2)
        context.stroke(box)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 0.12, blue: 0.12, alpha: 1))
        context.setLineWidth(line)
        context.stroke(box)
        return context.makeImage()
    }

    static func strokeWidth(forLongSide longSide: Int) -> CGFloat {
        max(3, (CGFloat(longSide) / 500).rounded())
    }

    /// JPEG at the usual quality, dropping it if that somehow doesn't fit the limit.
    static func jpeg(_ image: CGImage, byteLimit: Int = byteLimit) -> Data? {
        for quality in [quality, 0.5, 0.3] {
            if let data = encode(image, quality: quality), data.count < byteLimit { return data }
        }
        return nil
    }

    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
