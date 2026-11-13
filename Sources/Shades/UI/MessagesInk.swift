import AppKit
import ShadesCore

/// The roles every window draws with, from Messages and Settings to the cat's bubble, Ask box and panels, each one of
/// Opal's tokens, and the type roles at the text size and font you picked. `docs/design.md` says which goes where.
enum MessagesInk {
    /// How big what's said is, set when the app starts and when you pick one, and read as Messages draws, all on the
    /// main thread.
    static var textSize: TextSize = .standard
    /// Points added to every size what's said is drawn at, and the box you type in.
    private static var textStep: CGFloat { step(at: textSize) }
    private static func step(at size: TextSize) -> CGFloat {
        switch size {
        case .small: -1
        case .standard: 0
        case .large: 2
        case .larger: 4
        }
    }
    /// What's said, such as a message, a note or a search hit.
    static var body: CGFloat { body(at: textSize) }
    static func body(at size: TextSize) -> CGFloat { 13 + step(at: size) }
    /// Who said it, when and how many. It grows half as fast, so it stays quieter than what it's about.
    static var meta: CGFloat { 11 + textStep / 2 }
    /// Over what's said, such as a heading in a message or a search hit's name.
    static var title: CGFloat { 14 + textStep }
    /// A window's name, in its toolbar.
    static var toolbarTitle: CGFloat { 15 + textStep }
    /// Small capitals over a section or a card, such as CHANNELS. They grow as meta does.
    static var label: CGFloat { meta }
    /// The family Messages draws its words in, set the same way. `nil` is the system's.
    static var fontFamily: String?
    /// The system's own faces, which no family name reaches, by the names Font Book gives them.
    static let systemFaces: [(name: String, design: NSFontDescriptor.SystemDesign)] = [
        ("SF Pro", .default), ("New York", .serif), ("SF Pro Rounded", .rounded), ("SF Mono", .monospaced),
    ]

    /// A font for Messages' words in the chosen family, at this size and weight. A family that isn't on this Mac, such
    /// as one written into the settings file by hand, draws in the system's. `tabular` gives every digit one width, so a
    /// number that changes, such as an age or a count, holds still.
    static func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular, tabular: Bool = false, family: String? = MessagesInk.fontFamily) -> NSFont {
        let font = face(ofSize: size, weight: weight, family: family)
        guard tabular else { return font }
        let digits = font.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: digits, size: size) ?? font
    }

    private static func face(ofSize size: CGFloat, weight: NSFont.Weight, family: String?) -> NSFont {
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

    /// The content: a main window's inset panel and a floating panel's body.
    static let paper = Ink.hex(Opal.page)
    /// The chrome a main window's sidebar sits flush on.
    static let sidebar = Ink.hex(Opal.chrome)
    static let raised = Ink.hex(Opal.raised)
    /// Titles and figures.
    static let strong = Ink.hex(Opal.white)
    static let text = Ink.hex(Opal.body)
    /// Quieter words, such as times and captions, which read at 4.5:1 even on a row you hover or pick.
    static let soft = Ink.hex(Opal.secondary)
    /// Quieter still, only on paper, the sidebar or raised, and a control's edge.
    static let dim = Ink.hex(Opal.dim)
    /// Small capitals' words.
    static let labelColor = Ink.hex(Opal.white).withAlphaComponent(Opal.labelAlpha)
    static let line = Ink.hex(Opal.border)
    static let hover = Ink.hex(Opal.raised)
    static let press = Ink.hex(Opal.selected)
    /// What's filled with the accent, such as a ticked box, the focus ring or an unread bar. Never words.
    static let accent = Ink.hex(Opal.violet)
    static let onAccent = Ink.hex(Opal.white)
    /// Words in the accent, such as reply bars and links.
    static let link = Ink.hex(Opal.lilac)
    /// Why something didn't work, such as a message that couldn't be sent.
    static let danger = Ink.hex(Opal.errorText)
    /// The cat's one-word pill, a capsule of floating glass.
    static let pill = Ink.hex(Opal.raised)
    static let pillText = Ink.hex(Opal.body)
    /// A count of what's waiting on you, in the colour the cat glints when something does.
    static let badge = Ink.hex(Opal.error)
    static let onBadge = Ink.hex(Opal.page)

    /// Selected words, drawn the other way round so they read at 5.3:1 whatever they sit on: light words go dark on
    /// violet, and dark ones, on a kitten's bubble light enough for black words, go to body on the page, since violet
    /// can be as light as that bubble. A tint of the words' own colour fell under 4.5:1 on most kittens' bubbles.
    static func selection(on words: NSColor) -> [NSAttributedString.Key: Any] {
        let srgb = words.usingColorSpace(.sRGB) ?? text
        let rgb = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
            .reduce(UInt32(0)) { $0 << 8 | UInt32((min(max($1, 0), 1) * 255).rounded()) }
        let isLight = Opal.contrast(rgb, Opal.page) >= Opal.contrast(rgb, Opal.white)
        return isLight ? [.backgroundColor: accent, .foregroundColor: paper] : [.backgroundColor: paper, .foregroundColor: text]
    }

    /// Small capitals, such as CHANNELS: tracked out, medium, and white at 55%.
    static func label(_ words: String, size: CGFloat = MessagesInk.label) -> NSAttributedString {
        NSAttributedString(string: words.uppercased(), attributes: [
            .font: font(ofSize: size, weight: .medium),
            .foregroundColor: labelColor,
            .kern: size * 0.09,
        ])
    }
}
