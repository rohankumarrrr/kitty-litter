import CoreGraphics

enum ScreenGeometry {
    static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func pixelRect(of rect: CGRect, onDisplay display: CGRect, imageSize: CGSize) -> CGRect? {
        let visible = rect.intersection(display)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        let scaleX = imageSize.width / display.width
        let scaleY = imageSize.height / display.height
        let pixels = CGRect(
            x: (visible.minX - display.minX) * scaleX,
            y: (visible.minY - display.minY) * scaleY,
            width: visible.width * scaleX,
            height: visible.height * scaleY
        )
        return pixels.integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

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

    static func cappedPixelSize(points: CGSize, scale: CGFloat, longSide: CGFloat) -> CGSize {
        let pixels = CGSize(width: points.width * scale, height: points.height * scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > longSide else { return CGSize(width: pixels.width.rounded(), height: pixels.height.rounded()) }
        let shrink = longSide / longest
        return CGSize(width: (pixels.width * shrink).rounded(), height: (pixels.height * shrink).rounded())
    }
}
