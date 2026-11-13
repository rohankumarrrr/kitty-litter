/// Sizes and colours for the cat. The site draws it at 3x; a desktop cat gets 4x.
enum CatArt {
    static let grid = 16
    static let scale = 4
    static let points = grid * scale
}

enum CatTheme: Hashable {
    case light, dark

    /// Colours as 0xRRGGBB, the same ones the site uses.
    var palette: [Character: UInt32] {
        switch self {
        // On a light page: a black outline, and a jacket you can tell from it.
        case .light:
            return ["k": 0x111113, "w": 0xfbfaf6, "j": 0x2a2a2e, "z": 0xc9ccd2, "s": 0x0a0a0b, "g": 0xffffff, "p": 0xff5fa2]
        // On a dark page the outline has to be the light thing, or there's no cat.
        case .dark:
            return ["k": 0x8f8f95, "w": 0xfbfaf6, "j": 0x232327, "z": 0xc9ccd2, "s": 0x0a0a0b, "g": 0xffffff, "p": 0xff5fa2]
        }
    }

    var sleepZ: UInt32 {
        switch self {
        case .light: return 0x646464
        case .dark: return 0x9b9ba0
        }
    }
}

/// What the sunglasses glint is saying right now.
enum CatGlint: Hashable {
    case plain
    case listening(loudness: Int)
    case thinking(bright: Bool)
    case attention(bright: Bool)
    case party

    /// The site's `eyes` override: a colour for the `g` pixels, or `nil` for the usual white. They're Opal's status
    /// colours, so a kitten's dot says the same: mint when it's done, lilac while it works and rose when it needs you.
    var color: UInt32? {
        switch self {
        case .plain: return nil
        case .listening(let loudness): return [Opal.mix(Opal.good, Self.lens, 0.5), Opal.good, Opal.mix(Opal.good, 0xffffff, 0.5)][min(max(loudness, 0), 2)]
        case .thinking(let bright): return bright ? Opal.lilac : Opal.mix(Opal.lilac, Self.lens, 0.55)
        // Off means the lens itself, so the light really blinks.
        case .attention(let bright): return bright ? Opal.error : Self.lens
        case .party: return Opal.rimCyan
        }
    }

    private static let lens: UInt32 = 0x0a0a0b
}
