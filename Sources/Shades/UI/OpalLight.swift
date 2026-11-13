import AppKit

/// Opal's light, drawn the same way everywhere: the rimlit card, floating glass, the Rimlight tile, the rim gradient,
/// the meter and the field. Each draws in the current view, flipped or not, and `docs/design.md` has the
/// recipe each follows.
@MainActor
extension Opal {
    /// What lights a card or a tile: its rim and the glow rising from its bottom edge.
    struct Light: Equatable {
        var rim: UInt32
        var glow: UInt32

        /// `hsl(hue, 100%, 68%)` for the rim and 60% for the glow, as the card's CSS has it.
        static func hue(_ degrees: CGFloat) -> Light {
            Light(rim: Opal.hue(degrees, lightness: 0.68), glow: Opal.hue(degrees, lightness: 0.6))
        }

        /// A kitten's, in its own colour.
        static func of(_ color: UInt32) -> Light { Light(rim: color, glow: color) }

        static let shades = hue(Opal.shadesHue)

        /// A tile that isn't a kitten's, drifting teal to pink down a list.
        static func drifting(_ index: Int, of count: Int) -> Light {
            hue(172 + (344 - 172) * CGFloat(index) / CGFloat(max(count - 1, 1)))
        }
    }

    static let rim = NSGradient(colors: [rimCyan, rimViolet, rimPink].map(Ink.hex))!

    /// True black glass, lit only along its bottom edge. `shape` is its outline when that's more than `rect` rounded, such
    /// as the cat's bubble with its tail, which the light carries on around.
    static func card(in rect: NSRect, radius: CGFloat = Corner.card, light: Light, shape: NSBezierPath? = nil) {
        let shape = shape ?? NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        vertical(NSGradient(colors: [Ink.hex(cardTop).withAlphaComponent(cardTopAlpha), Ink.hex(cardBottom).withAlphaComponent(cardBottomAlpha)])!, in: rect)
        // radial-gradient(70% 90% at 50% 112%, glow 30%, transparent 72%) over the bottom 72%.
        let glowHeight = rect.height * 0.72
        glow(light.glow, alpha: 0.3, end: 0.72, center: NSPoint(x: rect.midX, y: bottom(of: rect) - up * glowHeight * 0.12), radii: NSSize(width: rect.width * 0.7, height: glowHeight * 0.9))
        NSGraphicsContext.restoreGraphicsState()

        let hairline = NSColor(white: 1, alpha: 0.07)
        ring(shape, width: 1, gradient: NSGradient(starting: hairline, ending: hairline)!, over: rect)
        ring(shape, width: 1.2, gradient: NSGradient(
            colors: [.clear, .clear, Ink.hex(light.rim).withAlphaComponent(0.55), Ink.hex(light.rim)],
            atLocations: [0, 0.58, 0.82, 1],
            colorSpace: .sRGB
        )!, over: rect)
    }

    /// What floats over other windows: dense violet-black glass with a hairline. `path` is the panel's shape, a
    /// balloon's tail and all.
    static func glass(_ path: NSBezierPath) {
        Ink.hex(raised).withAlphaComponent(0.94).setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// A black tile lit from below, for a glyph or a kitten's cat to go on.
    static func tile(in rect: NSRect, light: Light) {
        let side = min(rect.width, rect.height)
        let radius = side * 0.225
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        vertical(NSGradient(colors: [Ink.hex(cardTop), Ink.hex(cardBottom)])!, in: rect)
        glow(light.glow, alpha: 0.45, end: 1, center: NSPoint(x: rect.midX, y: bottom(of: rect)), radii: NSSize(width: rect.width, height: rect.height * 0.6))
        NSGraphicsContext.restoreGraphicsState()
        ring(shape, width: 1.5 * side / 40, gradient: NSGradient(
            colors: [NSColor(white: 1, alpha: 0.22), .clear, .clear, Ink.hex(light.rim)],
            atLocations: [0, 0.4, 0.6, 1],
            colorSpace: .sRGB
        )!, over: rect)
    }

    /// A line of the rim's light, such as the open tab's underline or the unread line.
    static func rimLine(in rect: NSRect) {
        rim.draw(in: rect, angle: 0)
    }

    /// A 3-point track, filled cyan to violet on plan and violet to pink past it, with a tick where it should be.
    static func meter(in rect: NSRect, fraction: CGFloat, over: Bool = false, tick: CGFloat? = nil) {
        let track = NSRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3)
        NSColor(white: 1, alpha: 0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        var filled = track
        filled.size.width = track.width * min(max(fraction, 0), 1)
        if filled.width > 0 {
            let fill = NSGradient(colors: (over ? [rimViolet, rimPink] : [rimCyan, rimViolet]).map(Ink.hex))!
            fill.draw(in: NSBezierPath(roundedRect: filled, xRadius: 1.5, yRadius: 1.5), angle: 0)
        }
        if let tick {
            NSColor.white.setFill()
            NSRect(x: track.minX + track.width * tick - 0.75, y: rect.midY - 4.5, width: 1.5, height: 9).fill()
        }
    }

    /// A box you type in, with a violet ring while it has the keyboard.
    static func field(in rect: NSRect, focused: Bool) {
        let radius = Corner.control
        Ink.hex(raised).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        Ink.hex(fieldEdge).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5).stroke()
        if focused { QuietFocus.ring(rect, radius: radius) }
    }

    // MARK: - Drawing them

    private static var isFlipped: Bool { NSGraphicsContext.current?.isFlipped ?? false }
    /// Which way is up in the current view.
    private static var up: CGFloat { isFlipped ? -1 : 1 }
    private static func bottom(of rect: NSRect) -> CGFloat { isFlipped ? rect.maxY : rect.minY }
    private static func top(of rect: NSRect) -> CGFloat { isFlipped ? rect.minY : rect.maxY }

    /// From the top of `rect` to its bottom, carrying on past either end in the colour there.
    private static func vertical(_ gradient: NSGradient, in rect: NSRect) {
        gradient.draw(from: NSPoint(x: rect.midX, y: top(of: rect)), to: NSPoint(x: rect.midX, y: bottom(of: rect)), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    }

    /// An elliptical glow from `color` at `alpha` in the middle to clear at `end` of the way out.
    private static func glow(_ color: UInt32, alpha: CGFloat, end: CGFloat, center: NSPoint, radii: NSSize) {
        guard radii.width > 0, radii.height > 0 else { return }
        let gradient = NSGradient(colors: [Ink.hex(color).withAlphaComponent(alpha), Ink.hex(color).withAlphaComponent(0)], atLocations: [0, end], colorSpace: .sRGB)!
        NSGraphicsContext.saveGraphicsState()
        let squash = NSAffineTransform()
        squash.translateX(by: center.x, yBy: center.y)
        squash.scaleX(by: 1, yBy: radii.height / radii.width)
        squash.concat()
        gradient.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: radii.width, options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A line `width` wide just inside `shape`'s edge, shaded from the top of `rect` to its bottom.
    private static func ring(_ shape: NSBezierPath, width: CGFloat, gradient: NSGradient, over rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        context.addPath(shape.cgPath)
        context.setLineWidth(width * 2)
        context.replacePathWithStrokedPath()
        context.clip()
        vertical(gradient, in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
}
