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
        guard let shape else {
            return kept("card \(radius)", in: rect, light: light) { drawCard(in: $0, light: light, shape: NSBezierPath(roundedRect: $0, xRadius: radius, yRadius: radius)) }
        }
        drawCard(in: rect, light: light, shape: shape)
    }

    static func drawCard(in rect: NSRect, light: Light, shape: NSBezierPath) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        vertical(cardGlass, in: rect)
        // radial-gradient(70% 90% at 50% 112%, glow 30%, transparent 72%) over the bottom 72%.
        let glowHeight = rect.height * 0.72
        glow(cached(&cardGlows, light.glow) { fading($0, alpha: 0.3, end: 0.72) }, center: NSPoint(x: rect.midX, y: bottom(of: rect) - up * glowHeight * 0.12), radii: NSSize(width: rect.width * 0.7, height: glowHeight * 0.9))
        // The hairline is one colour all the way round, so a line twice its width, cut by the shape, is it.
        NSColor(white: 1, alpha: 0.07).setStroke()
        context.addPath(shape.cgPath)
        context.setLineWidth(2)
        context.strokePath()
        // The rim is clear down to 58% of the way, so only the band below that is shaded, down past the bottom of the
        // shape, a bubble's tail and all.
        let outline = shape.bounds.union(rect).insetBy(dx: -2, dy: -2)
        let line = isFlipped ? rect.maxY - rect.height * 0.42 - 2 : rect.minY + rect.height * 0.42 + 2
        context.clip(to: isFlipped
            ? NSRect(x: outline.minX, y: line, width: outline.width, height: max(outline.maxY - line, 0))
            : NSRect(x: outline.minX, y: outline.minY, width: outline.width, height: max(line - outline.minY, 0)))
        context.addPath(shape.cgPath)
        context.setLineWidth(2.4)
        context.replacePathWithStrokedPath()
        context.clip()
        vertical(cached(&cardRims, light.rim) { rim in
            NSGradient(colors: [.clear, .clear, Ink.hex(rim).withAlphaComponent(0.55), Ink.hex(rim)], atLocations: [0, 0.58, 0.82, 1], colorSpace: .sRGB)!
        }, in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static let cardGlass = NSGradient(colors: [Ink.hex(cardTop).withAlphaComponent(cardTopAlpha), Ink.hex(cardBottom).withAlphaComponent(cardBottomAlpha)])!
    private static let tileGlass = NSGradient(colors: [Ink.hex(cardTop), Ink.hex(cardBottom)])!
    // Each light's gradients, made once, since a long conversation draws the same few over and over.
    private static var cardGlows: [UInt32: NSGradient] = [:]
    private static var cardRims: [UInt32: NSGradient] = [:]
    private static var tileGlows: [UInt32: NSGradient] = [:]
    private static var tileRims: [UInt32: NSGradient] = [:]

    /// Cards and tiles as they were last drawn, by size, place between pixels and light, since every message in sight
    /// draws its card again on each step of a scroll. A screenful or two is kept, the oldest going first, and all of
    /// it goes when The Kitty Litter closes.
    private static var kept: [String: (image: CGImage, bytes: Int)] = [:]
    private static var keptOrder: [String] = []
    static let keptLimit = 16 << 20
    /// What the kept pictures hold, at the screen's pixels.
    private(set) static var keptBytes = 0

    static func forgetKept() {
        kept = [:]
        keptOrder = []
        keptBytes = 0
    }

    private static func kept(_ kind: String, in rect: NSRect, light: Light, draw: (NSRect) -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Drawn on the very pixels it lands on, with the card where it falls between them, so it's copied rather than
        // smoothed. A window's drawing doesn't say its colours, so those are the screen's, which it draws in.
        let pixels = context.convertToDeviceSpace(rect).integral
        let box = context.convertToUserSpace(pixels)
        let inside = rect.offsetBy(dx: -box.minX, dy: -box.minY)
        let flipped = isFlipped
        guard let space = context.colorSpace ?? NSScreen.main?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return draw(rect) }
        let key = "\(kind) \(inside) \(pixels.size) \(light.rim) \(light.glow) \(flipped) \(space.name.map { $0 as String } ?? "")"
        guard let image = kept[key]?.image ?? keep(key, pixels: pixels, box: box, space: space, flipped: flipped, draw: { draw(inside) }) else { return draw(rect) }
        context.saveGState()
        context.interpolationQuality = .none
        if flipped {
            context.translateBy(x: box.minX, y: box.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: box.size))
        } else {
            context.draw(image, in: box)
        }
        context.restoreGState()
    }

    private static func keep(_ key: String, pixels: NSRect, box: NSRect, space: CGColorSpace, flipped: Bool, draw: () -> Void) -> CGImage? {
        guard pixels.width >= 1, pixels.height >= 1,
              let bitmap = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        bitmap.scaleBy(x: pixels.width / box.width, y: pixels.height / box.height)
        if flipped {
            bitmap.translateBy(x: 0, y: box.height)
            bitmap.scaleBy(x: 1, y: -1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: flipped)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.makeImage() else { return nil }
        let bytes = image.bytesPerRow * image.height
        // shortcut: the oldest drawn goes first rather than the least used, which is fine while a screenful fits.
        while keptBytes + bytes > keptLimit, !keptOrder.isEmpty {
            keptBytes -= kept.removeValue(forKey: keptOrder.removeFirst())?.bytes ?? 0
        }
        kept[key] = (image, bytes)
        keptOrder.append(key)
        keptBytes += bytes
        return image
    }

    private static func cached(_ gradients: inout [UInt32: NSGradient], _ color: UInt32, make: (UInt32) -> NSGradient) -> NSGradient {
        if let gradient = gradients[color] { return gradient }
        let gradient = make(color)
        gradients[color] = gradient
        return gradient
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
        kept("tile", in: rect, light: light) { drawTile(in: $0, light: light) }
    }

    static func drawTile(in rect: NSRect, light: Light) {
        let side = min(rect.width, rect.height)
        let radius = side * 0.225
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        vertical(tileGlass, in: rect)
        glow(cached(&tileGlows, light.glow) { fading($0, alpha: 0.45, end: 1) }, center: NSPoint(x: rect.midX, y: bottom(of: rect)), radii: NSSize(width: rect.width, height: rect.height * 0.6))
        NSGraphicsContext.restoreGraphicsState()
        ring(shape, width: 1.5 * side / 40, gradient: cached(&tileRims, light.rim) { rim in
            NSGradient(colors: [NSColor(white: 1, alpha: 0.22), .clear, .clear, Ink.hex(rim)], atLocations: [0, 0.4, 0.6, 1], colorSpace: .sRGB)!
        }, over: rect)
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

    /// `color` at `alpha` in the middle, clear at `end` of the way out.
    private static func fading(_ color: UInt32, alpha: CGFloat, end: CGFloat) -> NSGradient {
        NSGradient(colors: [Ink.hex(color).withAlphaComponent(alpha), Ink.hex(color).withAlphaComponent(0)], atLocations: [0, end], colorSpace: .sRGB)!
    }

    /// An elliptical glow, `gradient` from the middle out.
    private static func glow(_ gradient: NSGradient, center: NSPoint, radii: NSSize) {
        guard radii.width > 0, radii.height > 0 else { return }
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
