import AppKit
import XCTest
@testable import Shades

/// Opal Horizon, as `docs/design.md` writes it down, held where a test can: no orange anywhere, words that read on
/// what they sit on, kitten colours that stay soft and apart, and tokens that stay Opal's. Every value here is in the
/// repo, so it never reads anyone's own theme files.
@MainActor
final class DesignTests: XCTestCase {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources", isDirectory: true)

    /// Opal's own values, from its colour roles and its design notes.
    private static let opal: [String: UInt32] = [
        "chrome": 0x0a080d, "page": 0x0c0a10, "raised": 0x15121b, "control": 0x1b1723, "controlHover": 0x262030,
        "selected": 0x1e1830, "border": 0x241f2e, "chromeBorder": 0x1f1b27, "fieldEdge": 0x2b2536,
        "white": 0xffffff, "body": 0xe7e4ec, "secondary": 0xa09aad, "dim": 0x837d90, "faint": 0x5e586b,
        "violet": 0x8a6cff, "primary": 0x7458e8, "lilac": 0xb9a6ff,
        "info": 0x7fd6ff, "good": 0x7fe3c4, "warning": 0xf3e6a8, "error": 0xff7a9a, "errorText": 0xff97b1,
        "infoSurface": 0x132430, "warningSurface": 0x26231a, "errorSurface": 0x2a1420,
        "rimCyan": 0x45cfff, "rimViolet": 0x805cff, "rimPink": 0xff4fb8, "cardTop": 0x141318, "cardBottom": 0x060508,
    ]

    // MARK: - No orange

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

    // MARK: - Words read

    func testEveryWordRoleReadsOnEverySurfaceItSitsOn() {
        // Glass and cards float on the desktop, so they're checked over a white one too, the worst there is.
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
        ]
        for (role, words, surfaces) in pairs {
            for surface in surfaces {
                let ratio = Opal.contrast(Self.hex(words), Self.hex(surface))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(role) on \(Opal.hex(Self.hex(surface))) is \(ratio)")
            }
        }
    }

    // MARK: - Kittens

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

    // MARK: - Tokens stay Opal's

    func testEveryTokenIsOpals() {
        let tokens: [String: UInt32] = [
            "chrome": Opal.chrome, "page": Opal.page, "raised": Opal.raised, "control": Opal.control, "controlHover": Opal.controlHover,
            "selected": Opal.selected, "border": Opal.border, "chromeBorder": Opal.chromeBorder, "fieldEdge": Opal.fieldEdge,
            "white": Opal.white, "body": Opal.body, "secondary": Opal.secondary, "dim": Opal.dim, "faint": Opal.faint,
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

    // MARK: - Measuring

    /// Warm and strong enough to read as orange or amber, from red-orange to gold. Pale yellow is too soft to count.
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
