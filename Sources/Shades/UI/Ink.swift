import AppKit
import ShadesCore

/// An Opal token as AppKit draws it.
enum Ink {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]).map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
    }
}

extension AgentThread {
    /// The same colours as the glint, so a status always looks the same.
    var dotColor: NSColor { dot.map(Ink.hex) ?? MessagesInk.soft }

    /// As 0xRRGGBB, which a phone is sent. `nil` is the soft grey.
    var dot: UInt32? {
        if !pendingApprovals.isEmpty { return CatGlint.attention(bright: true).color }
        switch status {
        case .waitingForApproval, .waitingForAnswer: return CatGlint.attention(bright: true).color
        case .starting, .running: return CatGlint.thinking(bright: true).color
        case .completed: return CatGlint.listening(loudness: 1).color
        case .failed: return Opal.error
        case .idle, .interrupted: return nil
        }
    }
}
