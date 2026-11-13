import AppKit

/// Opal Horizon, The Kitty Litter's design system and its only look: black opal, with colour entering only as light.
/// `docs/design.md` says what each of these is for, and `DesignTests` holds them to Opal's values.
enum Opal {
    // Surfaces, from the window's frame up.
    static let chrome: UInt32 = 0x0a080d
    static let page: UInt32 = 0x0c0a10
    static let raised: UInt32 = 0x15121b
    static let control: UInt32 = 0x1b1723
    static let controlHover: UInt32 = 0x262030
    static let selected: UInt32 = 0x1e1830
    static let border: UInt32 = 0x241f2e
    static let chromeBorder: UInt32 = 0x1f1b27
    static let fieldEdge: UInt32 = 0x2b2536

    // Words.
    static let white: UInt32 = 0xffffff
    static let body: UInt32 = 0xe7e4ec
    static let secondary: UInt32 = 0xa09aad
    /// Under 4.5:1 on a control, a hovered row or a selected one, so only on chrome, page, raised and cards.
    static let dim: UInt32 = 0x837d90
    /// Opal's placeholder grey, which doesn't read at 4.5:1, so only for a disarmed control's words.
    static let faint: UInt32 = 0x5e586b
    static let labelAlpha: CGFloat = 0.55

    // Light.
    static let violet: UInt32 = 0x8a6cff
    static let primary: UInt32 = 0x7458e8
    /// A quarter of the way to violet, the furthest white words on it still read at 4.5:1.
    static let primaryHover: UInt32 = 0x7a5dee
    static let primaryPressed: UInt32 = 0x664dcc
    static let lilac: UInt32 = 0xb9a6ff

    // Status. Never orange: pale yellow is the only warm one.
    static let info: UInt32 = 0x7fd6ff
    static let good: UInt32 = 0x7fe3c4
    static let warning: UInt32 = 0xf3e6a8
    static let error: UInt32 = 0xff7a9a
    static let errorText: UInt32 = 0xff97b1
    static let infoSurface: UInt32 = 0x132430
    static let warningSurface: UInt32 = 0x26231a
    static let errorSurface: UInt32 = 0x2a1420

    // The rim, cyan through violet to pink.
    static let rimCyan: UInt32 = 0x45cfff
    static let rimViolet: UInt32 = 0x805cff
    static let rimPink: UInt32 = 0xff4fb8

    // A card's black glass, top to bottom.
    static let cardTop: UInt32 = 0x141318
    static let cardBottom: UInt32 = 0x060508
    static let cardTopAlpha: CGFloat = 0.91
    static let cardBottomAlpha: CGFloat = 0.94

    /// Each kitten's one identity colour, picked from this in its kitten.json: teal, sky, cornflower, indigo, orchid,
    /// plum, rosewood and sage.
    static let kittens: [UInt32] = [0x56afb3, 0x7fbde4, 0x6a8bcf, 0x706cbb, 0xb777bb, 0x9e5b82, 0xd799b1, 0x94b68c]
    /// Shades' own light, as a hue, which its jacket is too black to give.
    static let shadesHue: CGFloat = 245

    enum Corner {
        static let panel: CGFloat = 15
        static let card: CGFloat = 18
        /// A card floating on the desktop, as the cat's bubble does.
        static let floatingCard: CGFloat = 20
        static let control: CGFloat = 9
        static let popover: CGFloat = 16
        static let sheet: CGFloat = 24
    }

    enum Space {
        static let between: CGFloat = 24
        static let inside: CGFloat = 24
        /// A main window's content panel, in from its frame.
        static let inset: CGFloat = 8
    }

    /// `hsl(hue, 100%, lightness)`, as the card's CSS writes its light.
    static func hue(_ degrees: CGFloat, lightness: CGFloat) -> UInt32 {
        let chroma = 1 - abs(2 * lightness - 1)
        let side = (degrees / 60).truncatingRemainder(dividingBy: 6)
        let x = chroma * (1 - abs(side.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (CGFloat, CGFloat, CGFloat) = switch Int(side) {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        return [r, g, b].reduce(UInt32(0)) { $0 << 8 | UInt32(((($1 + m) * 255).rounded()).clamped(0, 255)) }
    }

    static func hex(_ color: UInt32) -> String {
        String(format: "#%06x", color & 0xffffff)
    }

    /// `amount` of the way from `a` to `b`.
    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { mixed, shift in
            let channel = Double((a >> shift) & 0xff) * (1 - amount) + Double((b >> shift) & 0xff) * amount
            return mixed | UInt32(channel.rounded()) << shift
        }
    }

    /// As WCAG measures it, from 1 to 21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func luminance(_ color: UInt32) -> Double {
        let channel = { (shift: UInt32) -> Double in
            let value = Double((color >> shift) & 0xff) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}

private extension CGFloat {
    func clamped(_ low: CGFloat, _ high: CGFloat) -> CGFloat { Swift.min(Swift.max(self, low), high) }
}
