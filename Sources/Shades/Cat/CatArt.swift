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
            return ["k": 0x111113, "w": 0xfbfaf6, "j": 0x2a2a2e, "z": 0xc9ccd2, "s": 0x0a0a0b, "g": 0xffffff, "p": 0xff5fa2, "o": 0xff5a14]
        // On a dark page the outline has to be the light thing, or there's no cat.
        case .dark:
            return ["k": 0x8f8f95, "w": 0xfbfaf6, "j": 0x232327, "z": 0xc9ccd2, "s": 0x0a0a0b, "g": 0xffffff, "p": 0xff5fa2, "o": 0xff5a14]
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

    /// The site's `eyes` override: a colour for the `g` pixels, or `nil` for the usual white.
    var color: UInt32? {
        switch self {
        case .plain: return nil
        case .listening(let loudness): return [0x25a866, 0x3fe08a, 0x8dffc0][min(max(loudness, 0), 2)]
        case .thinking(let bright): return bright ? 0xffc02e : 0x8c6d22
        // Off means the lens itself, so the light really blinks.
        case .attention(let bright): return bright ? 0xff3b5c : 0x0a0a0b
        case .party: return 0xffd84d
        }
    }
}
