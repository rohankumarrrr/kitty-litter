import AppKit

/// Inline markdown only. Links come out as plain words, so nothing in a message can act.
enum ChannelMarkdown {
    static let font = NSFont.systemFont(ofSize: 13)

    static func attributed(_ text: String, color: NSColor = Ink.text) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: plain)
        }

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes = plain
            let intent = run.inlinePresentationIntent ?? []
            var runFont = intent.contains(.stronglyEmphasized) ? NSFont.systemFont(ofSize: font.pointSize, weight: .semibold) : font
            if intent.contains(.emphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
            if intent.contains(.code) {
                runFont = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
                attributes[.backgroundColor] = Ink.hover
            }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            attributes[.font] = runFont
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}

/// Some text laid out at one width, cut short to a number of lines if asked. There's no text view
/// because selecting text needs a key window, which this window can never be.
final class ChannelTextBlock {
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer()
    private let storage: NSTextStorage
    private var fitted: (width: CGFloat, maxLines: Int?)?
    private(set) var height: CGFloat = 0
    /// Whether there's more than the lines shown.
    private(set) var isCut = false

    init(_ text: NSAttributedString) {
        storage = NSTextStorage(attributedString: text)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
    }

    @discardableResult
    func fit(width: CGFloat, maxLines: Int? = nil) -> CGFloat {
        if let fitted, fitted.width == width, fitted.maxLines == maxLines { return height }
        fitted = (width, maxLines)
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        isCut = false
        let lines = lineWidths
        if let maxLines, lines.count > maxLines {
            // A blank line at the end would look like the end of the message, so it stops short of one.
            let kept = lines.prefix(maxLines).lastIndex { $0 > 0 } ?? maxLines - 1
            container.maximumNumberOfLines = kept + 1
            container.lineBreakMode = .byTruncatingTail
            isCut = true
        }
        layoutManager.ensureLayout(for: container)
        height = ceil(layoutManager.usedRect(for: container).height)
        return height
    }

    func draw(at origin: NSPoint) {
        let glyphs = layoutManager.glyphRange(for: container)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }

    private var lineWidths: [CGFloat] {
        layoutManager.ensureLayout(for: container)
        var widths: [CGFloat] = []
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) { _, used, _, _, _ in
            widths.append(used.width)
        }
        return widths
    }
}
