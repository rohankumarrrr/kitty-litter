import AppKit
import ShadesCore

enum MessagesInk {
    static var textSize: TextSize = .standard
    private static var textStep: CGFloat { step(at: textSize) }
    private static func step(at size: TextSize) -> CGFloat {
        switch size {
        case .small: -1
        case .standard: 0
        case .large: 2
        case .larger: 4
        }
    }
    static var body: CGFloat { body(at: textSize) }
    static func body(at size: TextSize) -> CGFloat { 13 + step(at: size) }
    static var meta: CGFloat { 11 + textStep / 2 }
    static var title: CGFloat { 14 + textStep }
    static var toolbarTitle: CGFloat { 15 + textStep }
    static var label: CGFloat { meta }
    static var fontFamily: String?
    // Outside the repo: no font family name reaches the system's own faces, so these go by design.
    static let systemFaces: [(name: String, design: NSFontDescriptor.SystemDesign)] = [
        ("SF Pro", .default), ("New York", .serif), ("SF Pro Rounded", .rounded), ("SF Mono", .monospaced),
    ]

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

    static var picture: Data? { didSet { pictureImage = picture.flatMap(NSImage.init(data:)) } }
    private(set) static var pictureImage: NSImage?

    static let paper = Ink.hex(Opal.page)
    static let sidebar = Ink.hex(Opal.chrome)
    static let raised = Ink.hex(Opal.raised)
    static let strong = Ink.hex(Opal.white)
    static let text = Ink.hex(Opal.body)
    static let soft = Ink.hex(Opal.secondary)
    static let dim = Ink.hex(Opal.dim)
    static let labelColor = Ink.hex(Opal.white).withAlphaComponent(Opal.labelAlpha)
    static let line = Ink.hex(Opal.border)
    static let hover = Ink.hex(Opal.raised)
    static let press = Ink.hex(Opal.selected)
    static let accent = Ink.hex(Opal.violet)
    static let onAccent = Ink.hex(Opal.white)
    static let link = Ink.hex(Opal.lilac)
    static let danger = Ink.hex(Opal.errorText)
    static let pill = Ink.hex(Opal.raised)
    static let pillText = Ink.hex(Opal.body)
    static let badge = Ink.hex(Opal.error)
    static let onBadge = Ink.hex(Opal.page)

    static func selection(on words: NSColor) -> [NSAttributedString.Key: Any] {
        let srgb = words.usingColorSpace(.sRGB) ?? text
        let rgb = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
            .reduce(UInt32(0)) { $0 << 8 | UInt32((min(max($1, 0), 1) * 255).rounded()) }
        let isLight = Opal.contrast(rgb, Opal.page) >= Opal.contrast(rgb, Opal.white)
        return isLight ? [.backgroundColor: accent, .foregroundColor: paper] : [.backgroundColor: paper, .foregroundColor: text]
    }

    static func label(_ words: String, size: CGFloat = MessagesInk.label) -> NSAttributedString {
        NSAttributedString(string: words.uppercased(), attributes: [
            .font: font(ofSize: size, weight: .medium),
            .foregroundColor: labelColor,
            .kern: size * 0.09,
        ])
    }
}
