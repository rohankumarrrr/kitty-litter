enum CatArt {
    static let grid = 16
    static let scale = 4
    static let points = grid * scale
}

enum CatTheme: Hashable {
    case light, dark

    var palette: [Character: UInt32] {
        switch self {
        case .light:
            return ["k": 0x111113, "w": 0xfbfaf6, "j": 0x2a2a2e, "z": 0xc9ccd2, "s": 0x0a0a0b, "g": 0xffffff, "p": 0xff5fa2]
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

enum CatGlint: Hashable {
    case plain
    case listening(loudness: Int)
    case thinking(bright: Bool)
    case attention(bright: Bool)
    case party

    var color: UInt32? {
        switch self {
        case .plain: return nil
        case .listening(let loudness): return [Opal.mix(Opal.good, Self.lens, 0.5), Opal.good, Opal.mix(Opal.good, 0xffffff, 0.5)][min(max(loudness, 0), 2)]
        case .thinking(let bright): return bright ? Opal.lilac : Opal.mix(Opal.lilac, Self.lens, 0.55)
        case .attention(let bright): return bright ? Opal.error : Self.lens
        case .party: return Opal.rimCyan
        }
    }

    private static let lens: UInt32 = 0x0a0a0b
}
