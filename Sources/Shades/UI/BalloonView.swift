import AppKit

/// A floating panel of Opal's glass, with a small stepped tail that matches the pixels of the cat.
class BalloonView: NSView {
    var tailX: CGFloat? { didSet { needsDisplay = true } }
    var tailOnTop = false { didSet { needsDisplay = true } }

    static let radius = Opal.Corner.popover
    private static let step: CGFloat = 4

    /// The part of the view that's message rather than tail.
    var body: NSRect {
        var rect = bounds
        rect.size.height -= BubbleLayout.tailHeight
        if !tailOnTop { rect.origin.y += BubbleLayout.tailHeight }
        return rect.insetBy(dx: 0.5, dy: 0.5)
    }

    override func draw(_ dirtyRect: NSRect) {
        Opal.glass(outline())
    }

    private func outline() -> NSBezierPath {
        let rect = body
        let r = Self.radius
        let step = Self.step
        let path = NSBezierPath()
        let tail = tailX.map { min(max($0, rect.minX + r + step), rect.maxX - r - step) }

        path.move(to: NSPoint(x: rect.minX + r, y: rect.minY))
        if let tail, !tailOnTop {
            path.line(to: NSPoint(x: tail - step, y: rect.minY))
            path.line(to: NSPoint(x: tail - step, y: rect.minY - step * 2))
            path.line(to: NSPoint(x: tail, y: rect.minY - step * 2))
            path.line(to: NSPoint(x: tail, y: rect.minY - step))
            path.line(to: NSPoint(x: tail + step, y: rect.minY - step))
            path.line(to: NSPoint(x: tail + step, y: rect.minY))
        }
        path.line(to: NSPoint(x: rect.maxX - r, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 270, endAngle: 0)
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - r))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: 90)
        if let tail, tailOnTop {
            path.line(to: NSPoint(x: tail + step, y: rect.maxY))
            path.line(to: NSPoint(x: tail + step, y: rect.maxY + step))
            path.line(to: NSPoint(x: tail, y: rect.maxY + step))
            path.line(to: NSPoint(x: tail, y: rect.maxY + step * 2))
            path.line(to: NSPoint(x: tail - step, y: rect.maxY + step * 2))
            path.line(to: NSPoint(x: tail - step, y: rect.maxY))
        }
        path.line(to: NSPoint(x: rect.minX + r, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: 90, endAngle: 180)
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + r))
        path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }
}
