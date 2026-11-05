import CoreGraphics
import Foundation

/// Turns poses into 16×16 images. The layer scales them up with no smoothing, so
/// every art pixel lands on a whole number of screen pixels.
@MainActor
final class CatRenderer {
    private struct Key: Hashable {
        var pose: CatPose
        var theme: CatTheme
        var jacket: UInt32?
    }

    private var cache: [Key: CGImage] = [:]

    func image(for pose: CatPose, theme: CatTheme, jacket: UInt32? = nil) -> CGImage {
        let key = Key(pose: pose, theme: theme, jacket: jacket)
        if let image = cache[key] { return image }
        let image = Self.render(Self.pixels(for: pose, theme: theme, jacket: jacket))
        cache[key] = image
        return image
    }

    /// Premultiplied RGBA, row by row from the top.
    nonisolated static func pixels(for pose: CatPose, theme: CatTheme, jacket: UInt32? = nil) -> [UInt8] {
        var palette = theme.palette
        if let eyes = pose.glint.color { palette["g"] = eyes }
        if let jacket { palette["j"] = jacket }

        let size = CatArt.grid
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        func put(_ color: UInt32, x: Int, y: Int, alpha: Double = 1) {
            guard (0..<size).contains(x), (0..<size).contains(y) else { return }
            let i = (y * size + x) * 4
            bytes[i] = UInt8(Double((color >> 16) & 0xff) * alpha)
            bytes[i + 1] = UInt8(Double((color >> 8) & 0xff) * alpha)
            bytes[i + 2] = UInt8(Double(color & 0xff) * alpha)
            bytes[i + 3] = UInt8(255 * alpha)
        }

        for (y, row) in pose.frame.rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let color = palette[ch] else { continue }
                put(color, x: pose.flip ? size - 1 - x : x, y: y - pose.lift)
            }
        }

        if let step = pose.z {
            let z = Self.sleepZ[step % Self.sleepZ.count]
            for (y, row) in Self.zGlyph.enumerated() {
                for (x, ch) in row.enumerated() where ch == "z" {
                    put(theme.sleepZ, x: z.x + x, y: z.y + y, alpha: z.alpha)
                }
            }
        }
        return bytes
    }

    /// Whether the art has a pixel at this grid cell, counted from the top left.
    nonisolated static func isVisible(_ pose: CatPose, x: Int, y: Int) -> Bool {
        let size = CatArt.grid
        guard (0..<size).contains(x), (0..<size).contains(y) else { return false }
        let column = pose.flip ? size - 1 - x : x
        let rows = pose.frame.rows
        let row = y + pose.lift
        guard rows.indices.contains(row) else { return false }
        return rows[row][rows[row].index(rows[row].startIndex, offsetBy: column)] != "."
    }

    nonisolated private static let zGlyph = ["zzzz", "..z.", ".z..", "zzzz"]
    // The empty rows above a sleeping cat. It floats up and fades, as on the site.
    nonisolated private static let sleepZ: [(x: Int, y: Int, alpha: Double)] = [
        (10, 1, 0.45), (11, 1, 1), (11, 0, 0.7), (12, 0, 0.3),
    ]

    private static func render(_ pixels: [UInt8]) -> CGImage {
        let size = CatArt.grid
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
