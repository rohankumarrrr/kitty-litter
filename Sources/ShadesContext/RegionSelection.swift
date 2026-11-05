import CoreGraphics

/// One drag across the overlay, kept inside the display it started on.
struct RegionSelection: Equatable {
    /// Anything smaller was a click, or too thin to frame anything.
    static let minimumSide: CGFloat = 4

    let start: CGPoint
    var current: CGPoint
    let bounds: CGRect

    init(start: CGPoint, bounds: CGRect) {
        self.start = start
        self.current = start
        self.bounds = bounds
    }

    var rect: CGRect {
        let x = min(max(current.x, bounds.minX), bounds.maxX)
        let y = min(max(current.y, bounds.minY), bounds.maxY)
        return CGRect(
            x: min(start.x, x),
            y: min(start.y, y),
            width: abs(x - start.x),
            height: abs(y - start.y)
        )
    }

    var isDrag: Bool {
        rect.width >= Self.minimumSide && rect.height >= Self.minimumSide
    }
}
