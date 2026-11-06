import AppKit
import ShadesCore

/// Messages' colours: the theme you picked, or Ink's own. Only Messages and the phone take a theme, so the cat's
/// other windows stay as they are. Kittens keep their own colours either way.
enum MessagesInk {
    /// Set when the app starts and when you pick one, and read as Messages draws, all on the main thread.
    static var theme: ColorTheme?

    static var paper: NSColor { themed(\.paper) ?? Ink.paper }
    static var sidebar: NSColor { themed(\.sidebar) ?? Ink.hover }
    static var text: NSColor { themed(\.text) ?? Ink.text }
    static var soft: NSColor { themed(\.soft) ?? Ink.soft }
    static var line: NSColor { themed(\.line) ?? Ink.line }
    static var hover: NSColor { themed(\.hover) ?? Ink.hover }
    static var press: NSColor { themed(\.press) ?? Ink.press }

    /// The theme's light or dark, for the buttons, scrollers and cats it shares with the rest of the app. `nil` follows the system.
    static var appearance: NSAppearance? {
        theme.flatMap { NSAppearance(named: $0.isDark ? .darkAqua : .aqua) }
    }

    private static func themed(_ color: KeyPath<ColorTheme, UInt32>) -> NSColor? {
        theme.map { Ink.hex($0[keyPath: color]) }
    }
}
