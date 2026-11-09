import AppKit

/// A message's markdown as Messages draws it. A link is underlined and only says where it goes: pressing it asks
/// before anything opens, in the pane's link bar.
enum ChannelMarkdown {
    static var font: NSFont { MessagesInk.font(ofSize: 13 + MessagesInk.textStep) }
    private static var codeFont: NSFont { .monospacedSystemFont(ofSize: 12 + MessagesInk.textStep, weight: .regular) }
    static let copyRoom: CGFloat = 22
    /// More cells than this take seconds to lay out as a table, so a bigger one is drawn as text, the way code is.
    static let largestTable = 400
    /// How many lists deep an item's indent goes, so a deep one still has room for its words.
    private static let deepestIndent = 3

    /// GitHub's own colours for a pull request's state, which read the same on any bubble and any theme.
    static func chipColor(_ state: String?) -> NSColor {
        switch state {
        case "open": return Ink.hex(0x1f883d)
        case "merged": return Ink.hex(0x8250df)
        case "closed": return Ink.hex(0xcf222e)
        default: return Ink.hex(0x6e7781)
        }
    }

    static func attributed(_ text: String, color: NSColor = MessagesInk.text, pulls: [String: String] = [:]) -> NSAttributedString {
        attributed(Markup(text, pulls: pulls), color: color)
    }

    static func attributed(_ markup: Markup, color: NSColor = MessagesInk.text) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in markup.blocks.enumerated() {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacing = 6
            // A table's own margin doesn't count, so what follows one keeps its distance itself.
            if index > 0, markup.blocks[index - 1].kind == .table { style.paragraphSpacingBefore = 8 }
            switch block.kind {
            case .paragraph:
                result.append(line(block.spans ?? [], color: color, style: style))
            case .heading:
                result.append(line(block.spans ?? [], color: color, style: style, font: MessagesInk.font(ofSize: 14 + MessagesInk.textStep, weight: .semibold)))
            case .item:
                let indent = CGFloat(min((block.depth ?? 1) - 1, deepestIndent)) * 14
                let marker = block.marker ?? ""
                let markerWidth: CGFloat = marker.hasSuffix(".") ? 20 : 14
                style.firstLineHeadIndent = indent
                style.headIndent = indent + markerWidth
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
                style.paragraphSpacing = 3
                let item = NSMutableAttributedString(string: marker.isEmpty ? "\t" : "\(marker)\t", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
                item.append(line(block.spans ?? [], color: color, style: style))
                result.append(item)
            case .quote:
                let quote = NSTextBlock(fill: nil, padding: 8, color: color)
                quote.setWidth(0, type: .absoluteValueType, for: .padding, edge: .minY)
                quote.setWidth(0, type: .absoluteValueType, for: .padding, edge: .maxY)
                quote.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
                quote.setBorderColor(color.withAlphaComponent(0.35), for: .minX)
                style.textBlocks = [quote]
                result.append(line(block.spans ?? [], color: color, style: style))
            case .code:
                result.append(code(block.code ?? "", color: color, style: style))
            case .table:
                let rows = block.rows ?? []
                if rows.map(\.count).reduce(0, +) > largestTable {
                    let text = rows.map { $0.map { $0.map(\.text).joined() }.joined(separator: " | ") }.joined(separator: "\n")
                    result.append(code(text, color: color, style: style))
                } else {
                    result.append(table(rows, color: color))
                }
            case .rule:
                let rule = NSTextBlock(fill: nil, padding: 0, color: color)
                rule.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
                rule.setBorderColor(color.withAlphaComponent(0.25), for: .minY)
                rule.setWidth(4, type: .absoluteValueType, for: .margin, edge: .minY)
                style.textBlocks = [rule]
                result.append(NSAttributedString(string: "\u{200B}\n", attributes: [.font: MessagesInk.font(ofSize: 4), .paragraphStyle: style]))
            }
        }
        // Each block ends its own paragraph, and the last one ends the message.
        if result.string.hasSuffix("\n") { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        return result
    }

    private static func code(_ code: String, color: NSColor, style: NSMutableParagraphStyle) -> NSAttributedString {
        let block = NSTextBlock(fill: color.withAlphaComponent(0.08), padding: 8, color: color)
        // Room above the code for its Copy button.
        block.setWidth(copyRoom, type: .absoluteValueType, for: .padding, edge: .minY)
        style.textBlocks = [block]
        style.paragraphSpacing = 0
        style.lineSpacing = 1
        return NSAttributedString(string: code + "\n", attributes: [
            .font: codeFont, .foregroundColor: color, .paragraphStyle: style, .channelCode: ChannelCode(code),
        ])
    }

    /// Words ending in a newline, so the next block starts a paragraph of its own.
    private static func line(_ spans: [Markup.Span], color: NSColor, style: NSParagraphStyle, font: NSFont = font) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in spans { result.append(attributed(span, color: color, style: style, font: font)) }
        result.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        return result
    }

    private static func attributed(_ span: Markup.Span, color: NSColor, style: NSParagraphStyle, font: NSFont) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color, .paragraphStyle: style]
        var runFont = span.bold == true ? MessagesInk.font(ofSize: font.pointSize, weight: .semibold) : font
        if span.italic == true { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
        if span.code == true {
            runFont = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            attributes[.backgroundColor] = Ink.hover
        }
        if span.strike == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        var text = span.text
        if let link = span.link {
            attributes[.link] = link
            attributes[.toolTip] = link.absoluteString
            attributes[.cursor] = NSCursor.pointingHand
            if let pull = span.pull {
                // A chip, kept on one line, in its state's colour.
                text = "\u{00A0}" + ([text] + [pull.state].compactMap { $0 }).joined(separator: " · ").replacingOccurrences(of: " ", with: "\u{00A0}") + "\u{00A0}"
                runFont = MessagesInk.font(ofSize: font.pointSize - 1, weight: .semibold)
                attributes[.foregroundColor] = NSColor.white
                attributes[.channelChip] = chipColor(pull.state)
            } else {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
        }
        attributes[.font] = runFont
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func table(_ rows: [[[Markup.Span]]], color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let table = NSTextTable()
        table.numberOfColumns = max(rows.map(\.count).max() ?? 1, 1)
        table.setValue(100, type: .percentageValueType, for: .width)
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        for (rowIndex, row) in rows.enumerated() {
            for (column, cell) in row.enumerated() {
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(5, type: .absoluteValueType, for: .padding)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(color.withAlphaComponent(0.25))
                if rowIndex == 0 { block.backgroundColor = color.withAlphaComponent(0.06) }
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                result.append(line(cell, color: color, style: style, font: rowIndex == 0 ? MessagesInk.font(ofSize: font.pointSize, weight: .semibold) : font))
            }
        }
        return result
    }
}

extension NSAttributedString.Key {
    /// On a code block's words: the code, for its Copy button.
    static let channelCode = NSAttributedString.Key("ShadesChannelCode")
    /// On a pull request's chip: the colour it's drawn in.
    static let channelChip = NSAttributedString.Key("ShadesChannelChip")
}

/// One code block's code. Each is its own object, so two blocks with the same code are still two blocks.
final class ChannelCode: NSObject {
    let text: String
    init(_ text: String) { self.text = text }
}

private extension NSTextBlock {
    /// As wide as the words can go, which every block in a bubble is.
    convenience init(fill: NSColor?, padding: CGFloat, color: NSColor) {
        self.init()
        setValue(100, type: .percentageValueType, for: .width)
        setWidth(padding, type: .absoluteValueType, for: .padding)
        setWidth(3, type: .absoluteValueType, for: .margin, edge: .maxY)
        backgroundColor = fill
    }
}

/// Draws each pull request's chip as a pill behind its words.
private final class ChipLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.channelChip, in: characters) { value, range, _ in
            guard let fill = value as? NSColor else { return }
            fill.setFill()
            enumerateEnclosingRects(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil), withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                let pill = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0, dy: 1)
                NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            }
        }
    }
}

/// Some text laid out at one width, cut short to a number of lines if asked, in a text view you can select and copy
/// from. Pressing in it gives Messages the keyboard, the way pressing in the box does, which still leaves your app in
/// front, so Command-C has somewhere to go. It's measured without a view, and only gets one once the row it's in is
/// shown, since most of a long conversation never is.
final class ChannelTextBlock {
    private let layoutManager: NSLayoutManager = ChipLayoutManager()
    private let container = NSTextContainer()
    private let storage: NSTextStorage
    private var textView: ChannelTextView?
    private var origin = NSPoint.zero
    private var fitted: (width: CGFloat, maxLines: Int?)?
    private(set) var height: CGFloat = 0
    /// The widest line, so a bubble can be no wider than its words.
    private(set) var width: CGFloat = 0
    /// Where the words end, which for centred words is past `width`.
    private var right: CGFloat = 0
    private(set) var isCut = false
    /// Code, a table or a quote, which take the whole width, as they would on a page.
    private let hasBlocks: Bool
    /// Where words with blocks are cut, which their view stops drawing at.
    private var cutAt: CGFloat = 0

    init(_ text: NSAttributedString) {
        storage = NSTextStorage(attributedString: text)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
        var hasBlocks = false
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if (value as? NSParagraphStyle)?.textBlocks.isEmpty == false {
                hasBlocks = true
                stop.pointee = true
            }
        }
        self.hasBlocks = hasBlocks
    }

    @discardableResult
    func fit(width: CGFloat, maxLines: Int? = nil) -> CGFloat {
        if let fitted, fitted.width == width, fitted.maxLines == maxLines { return height }
        fitted = (width, maxLines)
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        // One line past the most it can show is enough to tell it's cut, however long it goes on. TextKit never
        // finishes stopping partway through a code block or table, so words with those are laid out whole.
        container.maximumNumberOfLines = hasBlocks ? 0 : maxLines.map { $0 + 1 } ?? 0
        container.lineBreakMode = .byWordWrapping
        isCut = false
        let rects = lineRects
        let lines = rects.map(\.width)
        if let maxLines, lines.count > maxLines {
            // A blank line at the end would look like the end of the message, so it stops short of one.
            let lastWithWords = lines.prefix(maxLines).lastIndex { $0 > 0 } ?? maxLines - 1
            if !hasBlocks {
                container.maximumNumberOfLines = lastWithWords + 1
                container.lineBreakMode = .byTruncatingTail
            }
            isCut = true
            cutAt = ceil(rects.prefix(lastWithWords + 1).map(\.maxY).max() ?? 0)
        }
        layoutManager.ensureLayout(for: container)
        height = hasBlocks && isCut ? cutAt : ceil(layoutManager.usedRect(for: container).height)
        // With a text view on it, the used rect is as wide as the container, so the lines say how wide the words are.
        let shown = lineRects
        right = hasBlocks ? width : ceil(shown.map(\.maxX).max() ?? 0)
        // From the line that starts furthest left, so a list's indent counts and centred words don't.
        self.width = hasBlocks ? width : right - floor(shown.map(\.minX).min() ?? 0)
        return height
    }

    var view: ChannelTextView {
        if let textView { return textView }
        let view = ChannelTextView(frame: .zero, textContainer: container)
        view.selectedTextAttributes = Self.selection(on: wordsColor)
        // Words with blocks are cut by their height, so nothing past it may show.
        view.clipsToBounds = true
        textView = view
        return view
    }

    /// Puts the words in `superview` with their top left at `origin`, as wide as they are, so pressing beside them
    /// doesn't start a selection. A row that isn't shown only remembers where they go.
    func place(at origin: NSPoint, in superview: NSView) {
        self.origin = origin
        if superview.superview != nil || textView?.superview === superview { show(in: superview) }
    }

    func show(in superview: NSView) {
        if view.superview !== superview { superview.addSubview(view) }
        view.frame = NSRect(x: origin.x, y: origin.y, width: right, height: height)
    }

    /// The same words drawn another way, such as in a theme's colours, without measuring them again.
    func restyle(_ text: NSAttributedString) {
        storage.setAttributedString(text)
        // A new text size lays out to a new height.
        fitted = nil
        textView?.selectedTextAttributes = Self.selection(on: wordsColor)
    }

    /// Each code block shown, by where it is from the words' top left, with its code, for a Copy button on it.
    var codeBlocks: [(frame: NSRect, code: String)] {
        var found: [(NSRect, String)] = []
        let shown = layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(for: container), actualGlyphRange: nil)
        storage.enumerateAttribute(.channelCode, in: shown) { value, range, _ in
            guard let code = value as? ChannelCode,
                  let block = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.first
            else { return }
            let frame = layoutManager.boundsRect(for: block, glyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil))
            if frame.height > 0, frame.minY < height { found.append((frame, code.text)) }
        }
        return found
    }

    private var wordsColor: NSColor? {
        storage.length > 0 ? storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil
    }

    /// A tint of the words' own colour shows on any bubble, where the system's blue might not.
    private static func selection(on words: NSColor?) -> [NSAttributedString.Key: Any] {
        [.backgroundColor: NSColor(name: nil) { _ in
            (words ?? MessagesInk.text).usingColorSpace(.sRGB)?.withAlphaComponent(0.3) ?? .selectedTextBackgroundColor
        }]
    }

    /// What each line's words take up.
    private var lineRects: [NSRect] {
        layoutManager.ensureLayout(for: container)
        var rects: [NSRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) { _, used, _, _, _ in
            rects.append(used)
        }
        return rects
    }
}

/// Words in Messages, which you can select and copy but not change. Like the reply in the cat's bubble, pressing in
/// them is what gives the window the keyboard, and only because you asked.
final class ChannelTextView: NSTextView {
    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isEditable = false
        isSelectable = true
        // Plain words when copied, so pasting doesn't bring along a bubble's white text. What's shown keeps its look.
        isRichText = false
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        usesFontPanel = false
        importsGraphics = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        // Nothing to check in words you can't change, and a window full of them shouldn't wake the spelling service.
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        linkTextAttributes = [:]
    }

    /// Pressing a link asks the pane to show where it goes, and opens nothing, as `ChannelPane.ask(toOpen:)` says.
    override func mouseDown(with event: NSEvent) {
        guard let link = link(at: convert(event.locationInWindow, from: nil)) else { return super.mouseDown(with: event) }
        clicked(onLink: link, at: 0)
    }

    /// However else AppKit uses a link, such as VoiceOver pressing it, it only shows where it goes too.
    override func clicked(onLink link: Any, at charIndex: Int) {
        guard let link = link as? URL else { return }
        tryToPerform(#selector(ChannelPane.ask(toOpen:)), with: link)
    }

    /// Copy is all a right-click offers. AppKit's own menu has Open Link and Open With, which open a link at once.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        return menu
    }

    /// The link drawn at a point in the view, if there is one.
    func link(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let textStorage, layoutManager.numberOfGlyphs > 0 else { return nil }
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(point) else { return nil }
        return textStorage.attribute(.link, at: layoutManager.characterIndexForGlyph(at: glyph), effectiveRange: nil) as? URL
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    /// A right-click is about these words too, so Copy in its menu has them.
    override func rightMouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    /// Only one selection at a time, as there would be in one long page.
    override func resignFirstResponder() -> Bool {
        setSelectedRange(NSRange(location: 0, length: 0))
        return super.resignFirstResponder()
    }
}
