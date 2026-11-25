import AppKit
import XCTest
@testable import Shades

@MainActor
final class DesignTests: XCTestCase {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources", isDirectory: true)

    private static let opal: [String: UInt32] = [
        "chrome": 0x0a080d, "page": 0x0c0a10, "raised": 0x15121b, "control": 0x1b1723, "controlHover": 0x262030,
        "selected": 0x1e1830, "border": 0x241f2e, "chromeBorder": 0x1f1b27, "fieldEdge": 0x2b2536,
        "white": 0xffffff, "black": 0x000000, "body": 0xe7e4ec, "secondary": 0xa09aad, "dim": 0x837d90, "faint": 0x5e586b,
        "violet": 0x8a6cff, "primary": 0x7458e8, "lilac": 0xb9a6ff,
        "info": 0x7fd6ff, "good": 0x7fe3c4, "warning": 0xf3e6a8, "error": 0xff7a9a, "errorText": 0xff97b1,
        "infoSurface": 0x132430, "warningSurface": 0x26231a, "errorSurface": 0x2a1420,
        "rimCyan": 0x45cfff, "rimViolet": 0x805cff, "rimPink": 0xff4fb8, "cardTop": 0x141318, "cardBottom": 0x060508,
    ]

    func testNothingTheAppDrawsIsOrange() throws {
        let literal = try NSRegularExpression(pattern: "(?:0x|#)([0-9a-fA-F]{6})(?![0-9a-fA-F])")
        let named = try NSRegularExpression(pattern: "NSColor\\.(system)?(orange|brown|yellow)\\b|\\.system(Orange|Brown|Yellow)\\b|:\\s*orange\\b")
        var found: [String] = []
        for file in try Self.swiftFiles() {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (number, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                let place = "\(file.lastPathComponent):\(number + 1)"
                for match in literal.matches(in: line, range: range) {
                    let hex = String(line[Range(match.range(at: 1), in: line)!])
                    if Self.isOrange(UInt32(hex, radix: 16)!) { found.append("\(place) #\(hex)") }
                }
                for match in named.matches(in: line, range: range) {
                    found.append("\(place) \(line[Range(match.range, in: line)!])")
                }
            }
        }
        XCTAssertEqual(found, [], "no orange anywhere, warnings included: pale yellow is the only warm one")
    }

    func testTheOrangeCheckKnowsOrangeFromOpalsColours() {
        for orange: UInt32 in [0xff5a14, 0xff9500, 0xffc02e, 0xd9730d, 0xb4532a, 0xffd84d] {
            XCTAssertTrue(Self.isOrange(orange), Opal.hex(orange))
        }
        for opal in Self.opal.values + Opal.kittens + [0xff3b30, 0xff5fa2] {
            XCTAssertFalse(Self.isOrange(opal), Opal.hex(opal))
        }
    }

    func testEveryWordRoleReadsOnEverySurfaceItSitsOn() {
        let floating = [Opal.mix(0xffffff, Opal.raised, 0.94), Opal.mix(0xffffff, Opal.cardTop, Opal.cardTopAlpha), Opal.cardBottom]
        let everywhere = [Opal.chrome, Opal.page, Opal.raised, Opal.control, Opal.controlHover, Opal.selected, Opal.cardTop] + floating
        let pairs: [(String, UInt32, [UInt32])] = [
            ("title", Opal.white, everywhere + [Opal.primary, Opal.primaryHover, Opal.primaryPressed]),
            ("body", Opal.body, everywhere + [Opal.infoSurface, Opal.warningSurface, Opal.errorSurface]),
            ("secondary", Opal.secondary, everywhere + [Opal.infoSurface, Opal.warningSurface, Opal.errorSurface]),
            ("dim", Opal.dim, [Opal.chrome, Opal.page, Opal.raised, Opal.cardTop, Opal.cardBottom]),
            ("lilac", Opal.lilac, everywhere),
            ("error words", Opal.errorText, everywhere + [Opal.errorSurface]),
            ("warning", Opal.warning, [Opal.page, Opal.raised, Opal.warningSurface]),
            ("info", Opal.info, [Opal.page, Opal.raised, Opal.infoSurface]),
            ("good", Opal.good, [Opal.page, Opal.raised]),
            ("a count", Opal.page, [Opal.error]),
        ]
        for (role, words, surfaces) in pairs {
            for surface in surfaces {
                let ratio = Opal.contrast(words, surface)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(role) \(Opal.hex(words)) on \(Opal.hex(surface)) is \(ratio)")
            }
        }
        for surface in everywhere {
            let label = Opal.mix(surface, Opal.white, Opal.labelAlpha)
            XCTAssertGreaterThanOrEqual(Opal.contrast(label, surface), 4.5, "small capitals on \(Opal.hex(surface))")
        }
    }

    func testTheRolesViewsDrawWithReadOnWhatTheySitOn() {
        let pairs: [(String, NSColor, [NSColor])] = [
            ("text", MessagesInk.text, [MessagesInk.paper, MessagesInk.sidebar, MessagesInk.hover, MessagesInk.press]),
            ("soft", MessagesInk.soft, [MessagesInk.paper, MessagesInk.sidebar, MessagesInk.hover, MessagesInk.press]),
            ("dim", MessagesInk.dim, [MessagesInk.paper, MessagesInk.sidebar, MessagesInk.raised]),
            ("link", MessagesInk.link, [MessagesInk.paper, MessagesInk.sidebar, MessagesInk.hover, MessagesInk.press]),
            ("danger", MessagesInk.danger, [MessagesInk.paper, MessagesInk.hover, MessagesInk.press]),
            ("pill", MessagesInk.pillText, [MessagesInk.pill]),
            ("badge", MessagesInk.onBadge, [MessagesInk.badge]),
            ("on the accent", MessagesInk.onAccent, [Ink.hex(Opal.primary)]),
            ("an open pull request's chip", ChannelMarkdown.chipWords("open"), [ChannelMarkdown.chipFill]),
            ("a merged pull request's chip", ChannelMarkdown.chipWords("merged"), [ChannelMarkdown.chipFill]),
            ("a closed pull request's chip", ChannelMarkdown.chipWords("closed"), [ChannelMarkdown.chipFill]),
            ("a pull request's chip", ChannelMarkdown.chipWords(nil), [ChannelMarkdown.chipFill]),
        ]
        for (role, words, surfaces) in pairs {
            for surface in surfaces {
                let ratio = Opal.contrast(Self.hex(words), Self.hex(surface))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(role) on \(Opal.hex(Self.hex(surface))) is \(ratio)")
            }
        }
    }

    func testKittenColoursAreSoftApartAndNeverAStatus() {
        let kittens = Opal.kittens
        XCTAssertGreaterThanOrEqual(kittens.count, 8, "enough for every kitten to have its own")
        XCTAssertEqual(ChannelSpeakerLook.palette, kittens, "a kitten with no colour gets one of these")
        for kitten in Demo.kittens {
            if let color = kitten.color { XCTAssertTrue(kittens.contains(color), "\(kitten.name) wears the palette") }
        }
        let statuses = [Opal.good, Opal.warning, Opal.error, Opal.info, Opal.lilac]
        for (index, color) in kittens.enumerated() {
            let (lightness, chroma) = Self.oklch(color)
            let name = Opal.hex(color)
            XCTAssertFalse(Self.isOrange(color), "\(name) is orange")
            XCTAssertLessThanOrEqual(chroma, 0.13, "\(name) is too loud")
            XCTAssertTrue((0.55...0.8).contains(lightness), "\(name) washes into the fur or goes muddy on black, at \(lightness)")
            for status in statuses {
                XCTAssertGreaterThanOrEqual(Self.distance(color, status), 0.06, "\(name) reads as \(Opal.hex(status))")
            }
            for other in kittens[(index + 1)...] {
                XCTAssertGreaterThanOrEqual(Self.distance(color, other), 0.08, "\(name) and \(Opal.hex(other)) look alike")
            }
        }
    }

    func testEveryTokenIsOpals() {
        let tokens: [String: UInt32] = [
            "chrome": Opal.chrome, "page": Opal.page, "raised": Opal.raised, "control": Opal.control, "controlHover": Opal.controlHover,
            "selected": Opal.selected, "border": Opal.border, "chromeBorder": Opal.chromeBorder, "fieldEdge": Opal.fieldEdge,
            "white": Opal.white, "black": Opal.black, "body": Opal.body, "secondary": Opal.secondary, "dim": Opal.dim, "faint": Opal.faint,
            "violet": Opal.violet, "primary": Opal.primary, "lilac": Opal.lilac,
            "info": Opal.info, "good": Opal.good, "warning": Opal.warning, "error": Opal.error, "errorText": Opal.errorText,
            "infoSurface": Opal.infoSurface, "warningSurface": Opal.warningSurface, "errorSurface": Opal.errorSurface,
            "rimCyan": Opal.rimCyan, "rimViolet": Opal.rimViolet, "rimPink": Opal.rimPink, "cardTop": Opal.cardTop, "cardBottom": Opal.cardBottom,
        ]
        for (name, value) in Self.opal {
            XCTAssertEqual(tokens[name].map(Opal.hex), Opal.hex(value), name)
        }
        XCTAssertEqual(Opal.Light.shades, Opal.Light(rim: 0x695cff, glow: 0x4433ff), "hsl(245, 100%, 68%) and 60%, as the card's CSS has it")
    }

    func testTheRolesViewsDrawWithAreOpalsTokens() {
        let roles: [(String, NSColor, UInt32)] = [
            ("paper", MessagesInk.paper, 0x0c0a10), ("sidebar", MessagesInk.sidebar, 0x0a080d), ("text", MessagesInk.text, 0xe7e4ec),
            ("soft", MessagesInk.soft, 0xa09aad), ("line", MessagesInk.line, 0x241f2e), ("hover", MessagesInk.hover, 0x15121b),
            ("press", MessagesInk.press, 0x1e1830), ("accent", MessagesInk.accent, 0x8a6cff), ("link", MessagesInk.link, 0xb9a6ff),
            ("danger", MessagesInk.danger, 0xff97b1),
        ]
        for (role, color, want) in roles {
            XCTAssertEqual(Opal.hex(Self.hex(color)), Opal.hex(want), role)
        }
        XCTAssertEqual(CatGlint.thinking(bright: true).color, Opal.lilac, "working")
        XCTAssertEqual(CatGlint.attention(bright: true).color, Opal.error, "needs you")
        XCTAssertEqual(CatGlint.listening(loudness: 1).color, Opal.good, "done")
    }

    func testACardOrTileDrawnAgainLooksTheSameAsDrawingItAfresh() {
        let light = Opal.Light.of(Opal.kittens[0])
        let card = NSRect(x: 64.25, y: 23, width: 201.37, height: 58.6)
        let tile = NSRect(x: 20, y: 101.3, width: 32, height: 32)
        let cases: [(name: String, afresh: () -> Void, kept: () -> Void)] = [
            ("card", { Opal.drawCard(in: card, light: light, shape: NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16)) }, { Opal.card(in: card, radius: 16, light: light) }),
            ("tile", { Opal.drawTile(in: tile, light: light) }, { Opal.tile(in: tile, light: light) }),
        ]
        for (name, afresh, kept) in cases {
            for flipped in [true, false] {
                let drawn = Self.drawn(flipped: flipped, afresh)
                for round in ["first", "again"] {
                    let (worst, off) = Self.difference(drawn, Self.drawn(flipped: flipped, kept))
                    XCTAssertLessThanOrEqual(worst, 3, "\(name) \(round), flipped \(flipped)")
                    XCTAssertLessThanOrEqual(off, 10, "\(name) \(round), flipped \(flipped)")
                }
            }
        }
    }

    func testACardsLightCarriesOnDownItsTail() {
        let body = NSRect(x: 40, y: 60, width: 200, height: 120)
        for flipped in [true, false] {
            let tail = NSRect(x: 120, y: flipped ? body.maxY - 1 : body.minY - 11, width: 12, height: 12)
            let shape = NSBezierPath(roundedRect: body, xRadius: 20, yRadius: 20)
            shape.append(NSBezierPath(rect: tail))
            let picture = Self.drawn(flipped: flipped) { Opal.card(in: body, light: .of(0x00ff00), shape: shape) }
            // Outside the repo: NSBitmapImageRep counts a pixel's y from the picture's top.
            let tip = flipped ? tail.maxY - 2 : picture.size.height - tail.minY - 2
            var pixel = [Int](repeating: 0, count: 4)
            picture.getPixel(&pixel, atX: Int((tail.minX + 0.5) * 2), y: Int(tip * 2))
            XCTAssertGreaterThan(pixel[1], 120, "flipped \(flipped): the tail's edge is lit, \(pixel)")
        }
    }

    func testDrawingTheLightAgainCostsAboutWhatAPlainFillDoes() {
        let light = Opal.Light.of(Opal.kittens[2])
        let card = NSRect(x: 8, y: 8, width: 300, height: 300)
        let tile = NSRect(x: 8, y: 8, width: 32, height: 32)
        let icon = QuietButton("Copy", style: .plain)
        icon.symbol = "doc.on.doc"
        icon.setFrameSize(NSSize(width: 26, height: 26))
        let cases: [(name: String, work: () -> Void, fill: NSRect, fills: Double)] = [
            ("card", { Opal.card(in: card, radius: 16, light: light) }, card, 10),
            ("tile", { Opal.tile(in: tile, light: light) }, tile, 9),
            ("icon", { icon.draw(icon.bounds) }, icon.bounds, 20),
        ]
        for (name, work, area, fills) in cases {
            let fill = { Ink.hex(Opal.control).setFill(); NSBezierPath(roundedRect: area, xRadius: 9, yRadius: 9).fill() }
            let (drawn, filled) = Self.timed(work, beside: fill)
            XCTAssertLessThan(drawn, filled * fills, "\(name) took \(drawn)s against \(filled)s for a fill")
        }
    }

    func testWhatsKeptStaysUnderItsLimitAndGoesWhenTheKittyLitterCloses() {
        Opal.forgetKept()
        _ = Self.picture(flipped: true) {
            Opal.card(in: NSRect(x: 8, y: 8, width: 300, height: 60), radius: 16, light: .shades)
            let one = Opal.keptBytes
            Opal.card(in: NSRect(x: 8, y: 8, width: 300, height: 60), radius: 16, light: .shades)
            XCTAssertEqual(Opal.keptBytes, one, "the same card again is the one kept")
            for height in stride(from: 100, to: 300, by: 4) {
                Opal.card(in: NSRect(x: 8, y: 8, width: 300, height: CGFloat(height)), radius: 16, light: .shades)
            }
        }
        XCTAssertGreaterThan(Opal.keptBytes, 0)
        XCTAssertLessThanOrEqual(Opal.keptBytes, Opal.keptLimit)
        ChannelsWindow().windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertEqual(Opal.keptBytes, 0)
    }

    private static func timed(_ work: () -> Void, beside fill: () -> Void) -> (Double, Double) {
        var works: [Double] = []
        var fills: [Double] = []
        _ = picture(flipped: true) {
            work()
            for _ in 0..<200 {
                works.append(once(work))
                fills.append(once(fill))
            }
        }
        return (works.min()!, fills.min()!)
    }

    private static func once(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    private final class Canvas: NSView {
        let upsideDown: Bool
        let work: () -> Void
        init(flipped: Bool, work: @escaping () -> Void) {
            upsideDown = flipped
            self.work = work
            super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 320))
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { upsideDown }
        override func draw(_ dirtyRect: NSRect) {
            Ink.hex(Opal.page).setFill()
            bounds.fill()
            work()
        }
    }

    private static func drawn(flipped: Bool, _ work: @escaping () -> Void) -> NSBitmapImageRep {
        let canvas = Canvas(flipped: flipped, work: work)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        return rep
    }

    private static func picture(flipped: Bool, _ work: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 320, height: 320)
        let context = NSGraphicsContext(cgContext: NSGraphicsContext(bitmapImageRep: rep)!.cgContext, flipped: flipped)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        if flipped {
            context.cgContext.translateBy(x: 0, y: rep.size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        Ink.hex(Opal.page).setFill()
        NSRect(origin: .zero, size: rep.size).fill()
        work()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> (worst: Int, off: Int) {
        var worst = 0, off = 0
        let (p, q) = (a.bitmapData!, b.bitmapData!)
        for y in 0..<a.pixelsHigh {
            var most = 0
            for x in 0..<a.bytesPerRow {
                let gap = abs(Int(p[y * a.bytesPerRow + x]) - Int(q[y * b.bytesPerRow + x]))
                most = max(most, gap)
                if x % 4 == 3 {
                    if most > 2 { off += 1 }
                    worst = max(worst, most)
                    most = 0
                }
            }
        }
        return (worst, off)
    }

    private static func isOrange(_ color: UInt32) -> Bool {
        let rgb = [16, 8, 0].map { CGFloat((color >> UInt32($0)) & 0xff) / 255 }
        let (high, low) = (rgb.max()!, rgb.min()!)
        guard high > 0, high - low > 0, high == rgb[0] else { return false }
        let hue = 60 * (rgb[1] - rgb[2]) / (high - low)
        return (10...50).contains(hue) && (high - low) / high >= 0.35 && high >= 0.35
    }

    private static func oklab(_ color: UInt32) -> (Double, Double, Double) {
        let linear = [16, 8, 0].map { shift -> Double in
            let value = Double((color >> UInt32(shift)) & 0xff) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = (linear[0], linear[1], linear[2])
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func oklch(_ color: UInt32) -> (lightness: Double, chroma: Double) {
        let (l, a, b) = oklab(color)
        return (l, (a * a + b * b).squareRoot())
    }

    private static func distance(_ x: UInt32, _ y: UInt32) -> Double {
        let (p, q) = (oklab(x), oklab(y))
        return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
    }

    private static func hex(_ color: NSColor) -> UInt32 {
        let srgb = color.usingColorSpace(.sRGB)!
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].reduce(UInt32(0)) { $0 << 8 | UInt32(($1 * 255).rounded()) }
    }

    private static func swiftFiles() throws -> [URL] {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
    }
}
