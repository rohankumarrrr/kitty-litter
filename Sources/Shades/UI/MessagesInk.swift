import AppKit
import ShadesCore

/// Messages' colours: the theme you picked, or Ink's own. Only Messages and the phone take a theme, so the cat's
/// other windows stay as they are. Kittens keep their own colours either way.
enum MessagesInk {
    /// Set when the app starts and when you pick one, and read as Messages draws, all on the main thread.
    static var theme: ColorTheme?
    /// How big what's said is, set the same way.
    static var textSize: TextSize = .standard
    /// Points added to every size what's said is drawn at, and the box you type in.
    static var textStep: CGFloat {
        switch textSize {
        case .small: -1
        case .standard: 0
        case .large: 2
        case .larger: 4
        }
    }
    /// The family Messages draws its words in, set the same way. `nil` is the system's.
    static var fontFamily: String?
    /// The system's own faces, which no family name reaches, by the names Font Book gives them.
    static let systemFaces: [(name: String, design: NSFontDescriptor.SystemDesign)] = [
        ("SF Pro", .default), ("New York", .serif), ("SF Pro Rounded", .rounded), ("SF Mono", .monospaced),
    ]

    /// A font for Messages' words in the chosen family, at this size and weight. A family that isn't on this Mac, such
    /// as one written into the settings file by hand, draws in the system's.
    static func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular, family: String? = MessagesInk.fontFamily) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let family else { return system }
        if let face = systemFaces.first(where: { $0.name == family }) {
            return system.fontDescriptor.withDesign(face.design).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family, .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == family else { return system }
        return font
    }

    /// Your picture, as the small JPEG `YourPicture` keeps, set when the app starts. `nil` keeps your blue square.
    static var picture: Data? { didSet { pictureImage = picture.flatMap(NSImage.init(data:)) } }
    private(set) static var pictureImage: NSImage?

    static var paper: NSColor { themed(\.paper) ?? Ink.paper }
    static var sidebar: NSColor { themed(\.sidebar) ?? Ink.hover }
    static var text: NSColor { themed(\.text) ?? Ink.text }
    static var soft: NSColor { themed(\.soft) ?? Ink.soft }
    static var line: NSColor { themed(\.line) ?? Ink.line }
    static var hover: NSColor { themed(\.hover) ?? Ink.hover }
    static var press: NSColor { themed(\.press) ?? Ink.press }
    /// The theme's accent, or the blue of your own messages, for what's filled with it, such as a ticked box.
    static var accent: NSColor { themed(\.accent) ?? Ink.hex(ChannelSpeakerLook.yours) }
    static var onAccent: NSColor { ChannelSpeakerLook.readable(on: theme?.accent ?? ChannelSpeakerLook.yours) }
    /// Reply bars and links, which Slack draws in its accent, made darker or lighter if they wouldn't read.
    static var link: NSColor { legible(\.link, else: ChannelSpeakerLook.yours) }
    /// Why something didn't work, such as a message that couldn't be sent.
    static var danger: NSColor { legible(\.danger, else: ColorTheme.red) }
    /// A count of what's waiting on you, in the colour the cat glints when something does.
    static var badge: NSColor { Ink.hex(CatGlint.attention(bright: true).color!) }
    static var onBadge: NSColor { ChannelSpeakerLook.readable(on: CatGlint.attention(bright: true).color!) }

    /// The theme's light or dark, for the buttons, scrollers and cats it shares with the rest of the app. `nil` follows the system.
    static var appearance: NSAppearance? {
        theme.flatMap { NSAppearance(named: $0.isDark ? .darkAqua : .aqua) }
    }

    private static func themed(_ color: KeyPath<ColorTheme, UInt32>) -> NSColor? {
        theme.map { Ink.hex($0[keyPath: color]) }
    }

    /// The theme's colour, or `own` made to read on Ink's paper in light or dark.
    private static func legible(_ color: KeyPath<ColorTheme, UInt32>, else own: UInt32) -> NSColor {
        themed(color) ?? NSColor(name: nil) { Ink.hex(ColorTheme.legible(own, on: $0.isDark ? 0x1d1d1f : 0xf9f9f9)) }
    }
}
