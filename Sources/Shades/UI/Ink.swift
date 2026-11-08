import AppKit
import ShadesCore

/// The site's colours, so the bubbles look like its messages.
enum Ink {
    static let paper = dynamic(light: 0xf9f9f9, dark: 0x1d1d1f)
    static let text = dynamic(light: 0x202020, dark: 0xececea)
    static let soft = dynamic(light: 0x646464, dark: 0x9b9ba0)
    static let pill = dynamic(light: 0x202020, dark: 0xececea)
    static let pillText = dynamic(light: 0xf9f9f9, dark: 0x0c0c0d)
    static let line = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.1)
    }
    static let hover = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.06)
    }
    static let press = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.11)
    }
    static let accent = hex(0xff5a14)

    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { $0.isDark ? hex(dark) : hex(light) }
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]).map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
    }
}

extension AgentThread {
    /// The same colours as the glint, so a status always looks the same.
    var dotColor: NSColor { dot.map(Ink.hex) ?? Ink.soft }

    /// As 0xRRGGBB, which a phone is sent. `nil` is the soft grey.
    var dot: UInt32? {
        if !pendingApprovals.isEmpty { return CatGlint.attention(bright: true).color }
        switch status {
        case .waitingForApproval, .waitingForAnswer: return CatGlint.attention(bright: true).color
        case .starting, .running: return CatGlint.thinking(bright: true).color
        case .completed: return CatGlint.listening(loudness: 1).color
        case .failed: return 0xff3b30
        case .idle, .interrupted: return nil
        }
    }
}
