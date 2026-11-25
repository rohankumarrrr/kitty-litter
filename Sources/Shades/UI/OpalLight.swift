import AppKit

@MainActor
extension Opal {
    struct Light: Equatable {
        var rim: UInt32
        var glow: UInt32

        static func hue(_ degrees: CGFloat) -> Light {
            Light(rim: Opal.hue(degrees, lightness: 0.68), glow: Opal.hue(degrees, lightness: 0.6))
        }

        static func of(_ color: UInt32) -> Light { Light(rim: color, glow: color) }

        static let shades = hue(Opal.shadesHue)

        static func drifting(_ index: Int, of count: Int) -> Light {
            hue(172 + (344 - 172) * CGFloat(index) / CGFloat(max(count - 1, 1)))
        }
    }

    static let rim = NSGradient(colors: [rimCyan, rimViolet, rimPink].map(Ink.hex))!

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
        let glowHeight = rect.height * 0.72
        glow(cached(&cardGlows, light.glow) { fading($0, alpha: 0.3, end: 0.72) }, center: NSPoint(x: rect.midX, y: bottom(of: rect) - up * glowHeight * 0.12), radii: NSSize(width: rect.width * 0.7, height: glowHeight * 0.9))
        Ink.hex(Opal.white).withAlphaComponent(Opal.hairlineAlpha).setStroke()
        context.addPath(shape.cgPath)
        context.setLineWidth(2)
        context.strokePath()
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
    private static var cardGlows: [UInt32: NSGradient] = [:]
    private static var cardRims: [UInt32: NSGradient] = [:]
    private static var tileGlows: [UInt32: NSGradient] = [:]
    private static var tileRims: [UInt32: NSGradient] = [:]

    private static var kept: [String: (image: CGImage, bytes: Int)] = [:]
    private static var keptOrder: [String] = []
    static let keptLimit = 16 << 20
    private(set) static var keptBytes = 0

    static func forgetKept() {
        kept = [:]
        keptOrder = []
        keptBytes = 0
    }

    private static func kept(_ kind: String, in rect: NSRect, light: Light, draw: (NSRect) -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let pixels = context.convertToDeviceSpace(rect).integral
        let box = context.convertToUserSpace(pixels)
        let inside = rect.offsetBy(dx: -box.minX, dy: -box.minY)
        let flipped = isFlipped
        guard let space = PictureDrawing.space ?? NSScreen.main?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return draw(rect) }
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

    static func glass(_ path: NSBezierPath) {
        Ink.hex(raised).withAlphaComponent(0.94).setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    static func tile(in rect: NSRect, light: Light) {
        kept("tile", in: rect, light: light) { drawTile(in: $0, light: light) }
    }

    static func drawTile(in rect: NSRect, light: Light, rimShare: CGFloat = 1.5 / 40) {
        let side = min(rect.width, rect.height)
        let radius = side * 0.225
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        vertical(tileGlass, in: rect)
        glow(cached(&tileGlows, light.glow) { fading($0, alpha: 0.45, end: 1) }, center: NSPoint(x: rect.midX, y: bottom(of: rect)), radii: NSSize(width: rect.width, height: rect.height * 0.6))
        NSGraphicsContext.restoreGraphicsState()
        ring(shape, width: rimShare * side, gradient: cached(&tileRims, light.rim) { rim in
            NSGradient(colors: [NSColor(white: 1, alpha: 0.22), .clear, .clear, Ink.hex(rim)], atLocations: [0, 0.4, 0.6, 1], colorSpace: .sRGB)!
        }, over: rect)
    }

    static func rimLine(in rect: NSRect) {
        rim.draw(in: rect, angle: 0)
    }

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

    static func field(in rect: NSRect, focused: Bool) {
        let radius = Corner.control
        Ink.hex(raised).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        Ink.hex(fieldEdge).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5).stroke()
        if focused { QuietFocus.ring(rect, radius: radius) }
    }

    private static var isFlipped: Bool { NSGraphicsContext.current?.isFlipped ?? false }
    private static var up: CGFloat { isFlipped ? -1 : 1 }
    private static func bottom(of rect: NSRect) -> CGFloat { isFlipped ? rect.maxY : rect.minY }
    private static func top(of rect: NSRect) -> CGFloat { isFlipped ? rect.minY : rect.maxY }

    private static func vertical(_ gradient: NSGradient, in rect: NSRect) {
        gradient.draw(from: NSPoint(x: rect.midX, y: top(of: rect)), to: NSPoint(x: rect.midX, y: bottom(of: rect)), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    }

    private static func fading(_ color: UInt32, alpha: CGFloat, end: CGFloat) -> NSGradient {
        NSGradient(colors: [Ink.hex(color).withAlphaComponent(alpha), Ink.hex(color).withAlphaComponent(0)], atLocations: [0, end], colorSpace: .sRGB)!
    }

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
