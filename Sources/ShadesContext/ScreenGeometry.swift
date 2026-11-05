import CoreGraphics

/// The three coordinate systems a focus region passes through.
///
/// AppKit's global points start at the bottom left of the primary display, with y going up.
/// Quartz, which ScreenCaptureKit and window lists use, starts at the top left of that same
/// display, with y going down. Screenshot pixels start at the top left of the captured display.
enum ScreenGeometry {
    /// Flipping is its own inverse, so this also converts Quartz back to AppKit.
    static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Where a Quartz rect lands in an image of a display, clipped to it. `nil` if it misses the display.
    static func pixelRect(of rect: CGRect, onDisplay display: CGRect, imageSize: CGSize) -> CGRect? {
        let visible = rect.intersection(display)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        // The ratio covers Retina scale and the size cap in one go.
        let scaleX = imageSize.width / display.width
        let scaleY = imageSize.height / display.height
        let pixels = CGRect(
            x: (visible.minX - display.minX) * scaleX,
            y: (visible.minY - display.minY) * scaleY,
            width: visible.width * scaleX,
            height: visible.height * scaleY
        )
        // Rounding outward means the mark never cuts into what you pointed at.
        return pixels.integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// The display showing most of a rect, as an index into `displays`.
    static func displayIndex(showing rect: CGRect, among displays: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, display) in displays.enumerated() {
            let overlap = rect.intersection(display)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }

    /// What to capture: where you pointed, else the front window's display, else the one under the mouse.
    static func displayToCapture(
        focusRegion: CGRect?,
        frontWindow: CGRect?,
        mouse: CGPoint,
        among displays: [CGRect]
    ) -> Int? {
        let mouseBox = CGRect(origin: mouse, size: CGSize(width: 1, height: 1))
        for candidate in [focusRegion, frontWindow, mouseBox] {
            if let candidate, let index = displayIndex(showing: candidate, among: displays) { return index }
        }
        return displays.isEmpty ? nil : 0
    }

    /// A display's pixel size, scaled down so its long side fits within the cap.
    static func cappedPixelSize(points: CGSize, scale: CGFloat, longSide: CGFloat) -> CGSize {
        let pixels = CGSize(width: points.width * scale, height: points.height * scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > longSide else { return CGSize(width: pixels.width.rounded(), height: pixels.height.rounded()) }
        let shrink = longSide / longest
        return CGSize(width: (pixels.width * shrink).rounded(), height: (pixels.height * shrink).rounded())
    }
}
